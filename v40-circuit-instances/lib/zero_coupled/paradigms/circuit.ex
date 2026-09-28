defmodule ZeroCoupled.Paradigms.Circuit do
  @moduledoc """
  A graph of named Step instances plus wires from `{instance, port}` to `{instance, input}`.
  Pushing into an instance delivers along the wires, depth first; outputs on unwired ports come
  back to the caller as the circuit's edge.
  """
  alias ZeroCoupled.Ports.Step
  defstruct parts: %{}, wires: %{}

  def new(parts), do: %__MODULE__{parts: Map.new(parts)}

  def wire(%__MODULE__{} = c, from, to),
    do: %{c | wires: Map.update(c.wires, from, [to], &(&1 ++ [to]))}

  def push(%__MODULE__{} = c, id, data) do
    case Step.push(Map.fetch!(c.parts, id), data) do
      {:quiet, part} ->
        {put_part(c, id, part), []}

      {:emit, outputs, part} ->
        Enum.reduce(outputs, {put_part(c, id, part), []}, &route(&1, id, &2))
    end
  end

  def part(%__MODULE__{parts: parts}, id), do: Map.fetch!(parts, id)

  defp route({port, payload}, id, {c, edge}) do
    case Map.get(c.wires, {id, port}, []) do
      [] ->
        {c, edge ++ [{{id, port}, payload}]}

      targets ->
        Enum.reduce(targets, {c, edge}, fn {to, input}, {c, edge} ->
          {c2, more} = push(c, to, {input, payload})
          {c2, edge ++ more}
        end)
    end
  end

  defp put_part(c, id, part), do: %{c | parts: Map.put(c.parts, id, part)}
end
