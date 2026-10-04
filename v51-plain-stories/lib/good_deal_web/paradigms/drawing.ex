defmodule GoodDealWeb.Paradigms.Drawing do
  @moduledoc """
  Draws wiring as a Mermaid flowchart by reading the clauses that run it. `mermaid/1` draws a page:
  each `wire/3` clause, each `handle_async/3` clause (a task's outcome), and each timer message; a
  `to` is an arrow to the story whose input it calls, labelled `port → input`. `mermaid_story/1`
  draws one story's inside: each browser event it handles, each `input/4` clause and each `wire/4`
  clause, where a `run` or `feed`
  is an arrow to the part it steps (a `feed` names the source it asks on the way) and `out` is an
  arrow out of the story. Every other call is a dotted arrow to the effect it lands on (an assign, a
  stream, a flash, a store call, a task, a timer, a patch), or a call by its function's name.
  """

  @doc "The page's diagram, read from the page module's own source."
  def mermaid(page), do: chart(clauses(page), nil)

  @doc "One story's inner wiring, read from the story module's own source."
  def mermaid_story(story) do
    only_part =
      case Map.keys(story.parts()) do
        [part] -> part
        _ -> nil
      end

    chart(clauses(story), only_part)
  end

  defp chart(clauses, only_part) do
    edges =
      for {from, port, body} <- clauses,
          call <- calls(body),
          edge = edge(from, port, call, only_part) do
        edge
      end

    Enum.join(["flowchart LR" | Enum.uniq(edges)], "\n") <> "\n"
  end

  defp clauses(module) do
    {_, found} =
      module.__info__(:compile)[:source]
      |> to_string()
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {kind, _, [{:wire, _, [_, key, {port, _} | _]}, [do: body]]} = node, acc
        when kind in [:def, :defp] and is_atom(key) ->
          {node, [{key, port, body} | acc]}

        {:def, _, [{:input, _, [_, port, _, _]}, [do: body]]} = node, acc when is_atom(port) ->
          {node, [{"in_#{port}((#{port}))", port, body} | acc]}

        {:def, _, [{:handle_event, _, [event, _, _, _]}, [do: body]]} = node, acc
        when is_binary(event) ->
          {node, [{~s(ev_#{event}[/"#{event}"/]), event, body} | acc]}

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

  defp calls({{:., _, [{:out, _, _}]}, _, args}), do: [{{nil, :out}, args}]
  defp calls({name, _, args}) when is_atom(name) and is_list(args), do: [{{nil, name}, args}]
  defp calls(_), do: []

  defp edge(from, port, {{nil, :run}, args}, only_part),
    do: ~s(  #{from} -->|"#{port} → #{fun_name(args)}"| #{first_atom(args) || only_part})

  defp edge(from, port, {{mod, :feed}, args}, only_part) when mod in [nil, :Steps] do
    {input, source} = feed(args)
    ~s(  #{from} -->|"#{port} via #{source} → #{input}"| #{first_atom(args) || only_part})
  end

  defp edge(from, port, {{nil, :to}, args}, _only_part) do
    [story, input | _] = Enum.filter(args, &(is_atom(&1) and &1 not in [nil, true, false]))
    ~s(  #{from} -->|"#{port} → #{input}"| #{story})
  end

  defp edge(from, port, {{nil, :out}, args}, _only_part) do
    {out, _} = Enum.find(args, &match?({atom, _} when is_atom(atom), &1))
    ~s(  #{from} -->|"#{port} → #{out}"| out_#{out}[["#{out}"]])
  end

  defp edge(from, port, call, _only_part), do: edge(from, port, call)

  defp edge(from, port, {{nil, :start_async}, args}),
    do: ~s(  #{from} -.->|"#{port}"| #{first_atom(args)}["task #{task_call(args)}"])

  defp edge(from, port, {{:Steps, timer_call}, args})
       when timer_call in [:start_timer, :stop_timer],
       do: ~s(  #{from} -.->|"#{port}"| timer_#{first_atom(args)}["timer #{first_atom(args)}"])

  defp edge(from, port, {{:Steps, :stream_change}, _}), do: sink(from, port, :stream)
  defp edge(from, port, {{:Steps, :patch}, _}), do: sink(from, port, :patch)

  defp edge(from, port, {{nil, effect}, _})
       when effect in [:assign, :put_flash, :push_navigate, :push_patch],
       do: sink(from, port, effect)

  defp edge(from, port, {{mod, fun}, _}) when mod not in [nil, :Steps, :Money, :Map, :String],
    do: ~s(  #{from} -.->|"#{port}"| call_#{mod}_#{fun}["call #{mod}.#{fun}"])

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

  # what a feed asks, by module and function: `&Carts.list_items/1`, `&AddLine.run(add_line, &1)`
  defp source(args) do
    Enum.find_value(args, fn
      {:&, _, _} = capture -> remote_name(capture)
      _ -> nil
    end)
  end

  defp remote_name(ast) do
    {_, name} =
      Macro.prewalk(ast, nil, fn
        {{:., _, [{:__aliases__, _, mod}, fun]}, _, _} = node, nil ->
          {node, "#{List.last(mod)}.#{fun}"}

        node, acc ->
          {node, acc}
      end)

    name
  end

  # the call a task's function makes: `fn -> Charge.call(charge, payment) end`
  defp task_call(args), do: Enum.find_value(args, &(match?({:fn, _, _}, &1) && remote_name(&1)))
end
