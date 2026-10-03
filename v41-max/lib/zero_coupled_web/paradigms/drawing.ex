defmodule ZeroCoupledWeb.Paradigms.Drawing do
  @moduledoc """
  Draws a page's route table as a Mermaid flowchart, from the same value the page routes by. A `pass`
  is an arrow from the instance that sent the output to the instance whose input gets it, labelled
  `port → input`; a `feed` names the configured instance it asks on the way; an `async` task is a node
  its outcome comes back from; every other route is a dotted arrow to the page effect it lands on.
  """

  def mermaid(routes) do
    edges =
      for {{from, port}, targets} <- Enum.sort(routes), target <- targets do
        edge(from, to_string(port), target)
      end

    Enum.join(["flowchart LR" | Enum.uniq(edges)], "\n") <> "\n"
  end

  defp edge(from, port, {:pass, {_component, id, input}}),
    do: ~s(  #{from} -->|"#{port} → #{input}"| #{id})

  defp edge(from, port, {:feed, {instance, _fun, {_component, id, input}}}),
    do: ~s(  #{from} -->|"#{port} via #{instance} → #{input}"| #{id})

  defp edge(from, port, {:async, {task, instance, _fun}}),
    do: ~s(  #{from} -.->|"#{port}"| #{task}["task #{instance}"])

  defp edge(from, port, {:call, {instance, _fun}}),
    do: ~s(  #{from} -.->|"#{port}"| call_#{instance}["call #{instance}"])

  defp edge(from, port, {:call, fun}),
    do: ~s(  #{from} -.->|"#{port}"| call_#{name(fun)}["call #{name(fun)}"])

  defp edge(from, port, {kind, _}),
    do: ~s(  #{from} -.->|"#{port}"| page_#{kind}["page: #{kind}"])

  defp name(fun), do: Function.info(fun)[:name]
end
