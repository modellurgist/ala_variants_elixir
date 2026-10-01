defmodule ZeroCoupled.Paradigms.Drawing do
  @moduledoc """
  Renders a circuit as a Mermaid flowchart: an instance is a box labelled with its kind and the
  configuration a reader needs (a sink's name or text, a feature's module, a named capture's
  function), and a wire is an arrow labelled `port → input`. Grounded outputs go to a `ground` node.
  """
  alias ZeroCoupled.Paradigms.{Adapter, Circuit}

  def mermaid(%Circuit{parts: parts, wires: wires, grounds: grounds}) do
    nodes = for {id, part} <- Enum.sort(parts), do: ~s(  #{id}["#{id}<br/>#{label(part)}"])

    edges =
      for {{from, port}, targets} <- Enum.sort(wires), {to, input} <- targets do
        ~s(  #{from} -->|"#{port} → #{input}"| #{to})
      end

    ground =
      if grounds == [],
        do: [],
        else: [
          "  ground((ground))"
          | for({from, port} <- Enum.sort(grounds), do: ~s(  #{from} -.->|"#{port}"| ground))
        ]

    Enum.join(["flowchart LR" | nodes ++ edges ++ ground], "\n") <> "\n"
  end

  defp label(%Adapter{module: m}), do: short(m)

  defp label(%kind{} = part) do
    detail =
      part
      |> Map.from_struct()
      |> Enum.flat_map(fn
        {_k, f} when is_function(f) ->
          [capture(f)]

        {k, v} when k in [:name, :text, :module, :id, :ms] and not is_nil(v) ->
          ["#{k}: #{show(v)}"]

        _ ->
          []
      end)

    Enum.join([short(kind) | detail], "<br/>")
  end

  defp capture(f) do
    info = Function.info(f)
    "#{short(info[:module])}.#{info[:name]}/#{info[:arity]}"
  end

  defp show(v) when is_atom(v), do: short(v)
  defp show(v) when is_binary(v), do: String.replace(v, ~s("), "'")
  defp show(v), do: inspect(v)

  defp short(mod) when is_atom(mod), do: mod |> inspect() |> String.split(".") |> List.last()
end
