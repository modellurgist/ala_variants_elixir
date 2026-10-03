defmodule ZeroCoupledWeb.Paradigms.Drawing do
  @moduledoc """
  Draws a page's bindings map as a Mermaid flowchart, from the same value the page runs. An input
  binding is an arrow from one feature to another, labelled `port → input`; a `via` binding names the
  configured instance it asks on the way; every other binding is a dotted arrow to the page effect it
  lands on (an assign, a stream, a flash, a call, a task, a timer, a patch).
  """

  def mermaid(bindings) do
    edges =
      for {{from, port}, targets} <- Enum.sort(bindings), target <- targets do
        edge(from, to_string(port), target)
      end

    Enum.join(["flowchart LR" | Enum.uniq(List.flatten(edges))], "\n") <> "\n"
  end

  defp edge(from, port, {:input, key, fun}),
    do: ~s(  #{from} -->|"#{port} → #{name(fun)}"| #{key})

  defp edge(from, port, {:via, callee, targets}),
    do: Enum.map(targets, &edge(from, "#{port} via #{name(callee)}", &1))

  defp edge(from, port, {:call, callee}),
    do: ~s(  #{from} -.->|"#{port}"| call_#{name(callee)}["call #{name(callee)}"])

  defp edge(from, port, {:async, task, callee}),
    do: ~s(  #{from} -.->|"#{port}"| #{task}["task #{name(callee)}"])

  defp edge(from, port, {:start_timer, timer, _ms}),
    do: ~s(  #{from} -.->|"#{port}"| timer_#{timer}["timer #{timer}"])

  defp edge(from, port, {:stop_timer, timer}),
    do: ~s(  #{from} -.->|"#{port}: stop"| timer_#{timer}["timer #{timer}"])

  defp edge(from, port, :redirect),
    do: ~s(  #{from} -.->|"#{port}"| page_redirect["page: redirect"])

  defp edge(from, port, target),
    do: ~s(  #{from} -.->|"#{port}"| page_#{elem(target, 0)}["page: #{elem(target, 0)}"])

  defp name(fun) when is_function(fun), do: Function.info(fun)[:name]
  defp name(instance), do: instance.__struct__ |> Module.split() |> List.last()
end
