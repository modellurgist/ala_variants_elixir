defmodule GoodDealWeb.Paradigms.Drawing do
  @moduledoc """
  Draws a page's wiring, and one story's, as Mermaid flowcharts by reading the clauses that run.
  On the page, each `wire/3` clause's `Story.input` is an arrow to the story whose input it calls,
  labelled `port → input`, and its other calls are dotted arrows to the page effects they land on.
  In a story, each `input/4` and `wire/4` clause is read the same way: a `Story.run` is an arrow to the
  part whose input it calls, a `send_out` an arrow to one of the story's outputs, and the rest are
  dotted arrows to what its view shows or the I/O it asks for.
  """
  @doc "The page's diagram: its stories and the links between them, read from its own source."
  def mermaid(page),
    do:
      chart(
        for {from, port, body} <- clauses(page), call <- calls(body), do: edge(from, port, call)
      )

  @doc "One story's diagram: its inputs, its parts and its outputs, read from the story's source."
  def mermaid_story(story) do
    chart(
      for {from, port, body} <- story_clauses(story),
          call <- calls(body),
          do: story_edge(from, port, call)
    )
  end

  defp chart(edges),
    do: Enum.join(["flowchart LR" | Enum.uniq(Enum.reject(edges, &is_nil/1))], "\n") <> "\n"

  defp story_clauses(story) do
    {_, found} =
      story
      |> quoted()
      |> Macro.prewalk([], fn
        {:def, _, [{:wire, _, [_, _, part, {port, _}]}, [do: body]]} = node, acc
        when is_atom(part) ->
          {node, [{part, port, body} | acc]}

        {:def, _, [{:input, _, [_, _, port, _]}, [do: body]]} = node, acc when is_atom(port) ->
          {node, [{"in_#{port}((#{port}))", port, body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp quoted(module),
    do:
      module.__info__(:compile)[:source]
      |> to_string()
      |> File.read!()
      |> Code.string_to_quoted!()

  defp clauses(page) do
    {_, found} =
      page
      |> quoted()
      |> Macro.prewalk([], fn
        {kind, _, [{:wire, _, [_, key, {port, _}]}, [do: body]]} = node, acc
        when kind in [:def, :defp] and is_atom(key) ->
          {node, [{key, port, body} | acc]}

        {:def, _, [{:handle_async, _, [task, _, _]}, [do: body]]} = node, acc
        when is_atom(task) ->
          {node, [{task, :done, body} | acc]}

        {:def, _, [{:handle_info, _, [{:{}, _, [:timer, timer, _]}, _]}, [do: body]]} = node,
        acc ->
          {node, [{"timer_#{timer}", :fired, body} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  # the calls a clause body makes, in order, as {name, args}: a pipe's stages and a block's
  # statements, but not the calls inside their arguments (a capture's target, a config read)
  defp calls({:|>, _, [left, right]}), do: calls(left) ++ calls(right)
  defp calls({:__block__, _, statements}), do: Enum.flat_map(statements, &calls/1)
  defp calls({:noreply, expr}), do: calls(expr)

  defp calls({{:., _, [{:__aliases__, _, mod}, name]}, _, args}) when is_list(args),
    do: [{{List.last(mod), name}, args}]

  defp calls({name, _, args}) when is_atom(name) and is_list(args), do: [{{nil, name}, args}]
  defp calls(_), do: []

  defp edge(from, port, {{:Story, :input}, args}) do
    [story, input | _] = Enum.filter(args, &(is_atom(&1) and &1 not in [nil, true, false]))
    ~s(  #{from} -->|"#{port} → #{input}"| #{story})
  end

  defp edge(from, port, {{nil, :run}, args}),
    do: ~s(  #{from} -->|"#{port} → #{fun_name(args)}"| #{first_atom(args)})

  defp edge(from, port, {{:Steps, :feed}, args}) do
    {input, source} = feed(args)
    ~s(  #{from} -->|"#{port} via #{source} → #{input}"| #{first_atom(args)})
  end

  defp edge(from, port, {{:Steps, :call}, args}),
    do: ~s(  #{from} -.->|"#{port}"| call_#{source(args)}["call #{source(args)}"])

  defp edge(from, port, {{:Steps, :async}, args}),
    do: ~s(  #{from} -.->|"#{port}"| #{first_atom(args)}["task #{source(args)}"])

  defp edge(from, port, {{:Steps, timer_call}, args})
       when timer_call in [:start_timer, :stop_timer],
       do: ~s(  #{from} -.->|"#{port}"| timer_#{first_atom(args)}["timer #{first_atom(args)}"])

  defp edge(from, port, {{:Steps, :stream_change}, _}), do: sink(from, port, :stream)
  defp edge(from, port, {{:Steps, :patch}, _}), do: sink(from, port, :patch)

  defp edge(from, port, {{nil, effect}, _})
       when effect in [:assign, :put_flash, :push_navigate, :push_patch],
       do: sink(from, port, effect)

  defp edge(from, port, {{mod, fun}, _}) when mod not in [nil, :Steps, :Money, :Map, :String],
    do: ~s(  #{from} -.->|"#{port}"| call_#{fun}["call #{mod}.#{fun}"])

  defp edge(_from, _port, _call), do: nil

  defp sink(from, port, kind), do: ~s(  #{from} -.->|"#{port}"| page_#{kind}["page: #{kind}"])

  defp story_edge(from, port, {{:Story, :run}, args}),
    do: ~s(  #{from} -->|"#{port} → #{fun_name(args)}"| #{first_atom(args)})

  defp story_edge(from, port, {{:Story, :feed}, args}) do
    {input, source} = feed(args)
    ~s(  #{from} -->|"#{port} via #{source} → #{input}"| #{first_atom(args)})
  end

  defp story_edge(from, port, {{:Story, :send_out}, args}),
    do: "  #{from} -->|\"#{port}\"| #{out(first_atom(args))}"

  defp story_edge(from, port, {{:Story, :send_out_answer}, args}),
    do: "  #{from} -->|\"#{port} via #{source(args)}\"| #{out(first_atom(args))}"

  defp story_edge(from, port, {{:Story, :call}, args}),
    do: ~s(  #{from} -.->|"#{port}"| call_#{source(args)}["call #{source(args)}"])

  defp story_edge(from, port, {{:Story, :async}, args}),
    do: ~s(  #{from} -.->|"#{port}"| task_#{source(args)}["task #{source(args)}"])

  defp story_edge(from, port, {{mod, timer}, args})
       when {mod, timer} in [{:Story, :start_timer}, {:Sinks, :stop_timer}],
       do: ~s(  #{from} -.->|"#{port}"| timer_#{first_atom(args)}["timer #{first_atom(args)}"])

  defp story_edge(from, port, {{:Story, :show}, _}), do: view(from, port, :show)
  defp story_edge(from, port, {{:Sinks, kind}, _}), do: view(from, port, kind)

  defp story_edge(from, port, {{nil, effect}, _}) when effect in [:put_flash, :push_navigate],
    do: view(from, port, effect)

  defp story_edge(from, port, {{mod, fun}, _}) when mod not in [nil, :Story, :Sinks],
    do: ~s(  #{from} -.->|"#{port}"| call_#{fun}["call #{mod}.#{fun}"])

  defp story_edge(_from, _port, _call), do: nil

  defp out(port), do: "out_#{port}((#{port}))"
  defp view(from, port, kind), do: ~s(  #{from} -.->|"#{port}"| view_#{kind}["view: #{kind}"])

  defp first_atom(args), do: Enum.find(args, &(is_atom(&1) and &1 not in [nil, true, false]))

  # the name of the function a capture calls: `&Cart.receive/2` or `&Undo.capture(&1, item)`
  defp fun_name(args) do
    Enum.find_value(args, fn
      {:&, _, _} = capture -> capture_name(capture)
      _ -> nil
    end)
  end

  defp capture_name(capture) do
    {_, name} =
      Macro.prewalk(capture, nil, fn
        {{:., _, [_, name]}, _, _} = node, nil -> {node, name}
        node, acc -> {node, acc}
      end)

    name
  end

  # a feed's input (the first capture) and the source it asks for the payload (the argument after it)
  defp feed(args) do
    [input | rest] = Enum.drop_while(args, &(not match?({:&, _, _}, &1)))
    {capture_name(input), source(Enum.take(rest, 1))}
  end

  # what a feed, call or task asks: a named instance `{:name, fun}`, or a function capture
  defp source(args) do
    Enum.find_value(args, fn
      {name, {:&, _, _}} when is_atom(name) -> name
      {:&, _, _} = capture -> capture_name(capture)
      _ -> nil
    end)
  end
end
