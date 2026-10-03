defmodule ZeroCoupledWeb.Paradigms.Drawing do
  @moduledoc """
  Draws a page's wiring as a Mermaid flowchart by reading the clauses that run: each `handle_info`
  clause for a port output `{instance, port, payload}` or a broadcast fact, and each `handle_async`
  clause for a task's outcome. A `send_update` is an arrow to the instance whose input it calls,
  labelled `port → input`; a `start_async` is an arrow to the task, whose outcome clause carries on
  from it; every other call is a dotted arrow to the page effect it lands on.
  """

  @doc "The page's diagram, read from the page module's own source."
  def mermaid(page) do
    edges =
      for {from, port, body} <- clauses(page), call <- calls(body), do: edge(from, port, call)

    Enum.join(["flowchart LR" | Enum.uniq(Enum.reject(edges, &is_nil/1))], "\n") <> "\n"
  end

  defp clauses(page) do
    {_, found} =
      page.__info__(:compile)[:source]
      |> to_string()
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:def, _, [head, [do: body]]} = node, acc -> {node, clause(head, body) ++ acc}
        node, acc -> {node, acc}
      end)

    Enum.reverse(found)
  end

  defp clause({:when, _, [head | _]}, body), do: clause(head, body)

  defp clause({:handle_info, _, [{:{}, _, [name, port, _]}, _]}, body) when is_atom(name),
    do: [{name, port, body}]

  defp clause({:handle_info, _, [{:=, _, [{:%, _, [{:__aliases__, _, mod}, _]}, _]}, _]}, body),
    do: [{fact(mod), :fact, body}]

  defp clause({:handle_info, _, [{:%, _, [{:__aliases__, _, mod}, _]}, _]}, body),
    do: [{fact(mod), :fact, body}]

  defp clause({:handle_async, _, [task, outcome, _]}, body) when is_atom(task),
    do: [{task, outcome_name(outcome), body}]

  defp clause(_head, _body), do: []

  defp fact(mod), do: mod |> List.last() |> to_string() |> Macro.underscore()

  defp outcome_name({:ok, {:ok, _}}), do: :ok
  defp outcome_name({:ok, {:error, _}}), do: :error
  defp outcome_name({:exit, _}), do: :exit
  defp outcome_name(_), do: :ok

  # the calls a clause body makes, in order: a pipe's stages and a block's statements
  defp calls({:|>, _, [left, right]}), do: calls(left) ++ calls(right)
  defp calls({:__block__, _, statements}), do: Enum.flat_map(statements, &calls/1)
  defp calls({:noreply, expr}), do: calls(expr)

  defp calls({{:., _, [{:__aliases__, _, mod}, name]}, _, args}) when is_list(args),
    do: [{{List.last(mod), name}, args}]

  defp calls({name, _, args}) when is_atom(name) and is_list(args), do: [{{nil, name}, args}]
  defp calls(_), do: []

  defp edge(from, port, {{nil, :send_update}, args}) do
    opts = Enum.find(args, &is_list/1)
    {input, _} = Enum.find(opts, fn {key, _} -> key != :id end)
    ~s(  #{from} -->|"#{port} → #{input}"| #{opts[:id]})
  end

  defp edge(from, port, {{nil, :start_async}, args}) do
    task = Enum.find(args, &(is_atom(&1) and &1 not in [nil, true, false]))
    ~s(  #{from} -.->|"#{port}"| #{task}["task #{asks(args)}"])
  end

  defp edge(from, port, {{nil, effect}, _})
       when effect in [:assign, :put_flash, :push_patch, :redirect],
       do: ~s(  #{from} -.->|"#{port}"| page_#{effect}["page: #{effect}"])

  defp edge(from, port, {{mod, fun}, _}) when mod != nil,
    do: ~s(  #{from} -.->|"#{port}"| call_#{fun}["call #{mod}.#{fun}"])

  defp edge(_from, _port, _call), do: nil

  # the call a task's function makes: `fn -> AddLine.run(add_line, product) end`
  defp asks(args) do
    Enum.find_value(args, fn
      {:fn, _, [{:->, _, [_, {{:., _, [{:__aliases__, _, mod}, name]}, _, _}]}]} ->
        "#{List.last(mod)}.#{name}"

      _ ->
        nil
    end)
  end
end
