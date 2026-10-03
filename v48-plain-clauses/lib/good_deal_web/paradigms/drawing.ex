defmodule GoodDealWeb.Paradigms.Drawing do
  @moduledoc """
  Draws a page's wiring as a Mermaid flowchart by reading its clauses, the same ones the page runs:
  each `wire/3` clause, each `handle_async/3` clause (a task's outcome), and each timer message. A
  `run` in a clause is an arrow to the feature whose input it calls, labelled `port → input`; a `feed`
  names the source it asks on the way; every other call is a dotted arrow to the page effect it
  lands on (an assign, a stream, a flash, a store call, a task, a timer, a patch). A clause that calls
  something else the drawing doesn't know is drawn as a call by its function's name.
  """

  @doc "The page's diagram, read from the page module's own source."
  def mermaid(page) do
    edges =
      for {from, port, body} <- clauses(page),
          call <- calls(body),
          edge = edge(from, port, call) do
        edge
      end

    Enum.join(["flowchart LR" | Enum.uniq(edges)], "\n") <> "\n"
  end

  defp clauses(page) do
    {_, found} =
      page.__info__(:compile)[:source]
      |> to_string()
      |> File.read!()
      |> Code.string_to_quoted!()
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
