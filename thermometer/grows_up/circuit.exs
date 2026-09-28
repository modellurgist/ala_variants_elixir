# Spray 1.6.5 without processes: a pure graph of named instances plus a runner.
Code.require_file("dataflow.exs", __DIR__)

# A pure graph of wired instances. Emissions from a part with no outgoing wire leave
# the circuit, so the caller gets them back without naming any intermediate value.
defmodule Circuit do
  defstruct parts: %{}, wires: %{}

  def new(parts), do: %__MODULE__{parts: Map.new(parts)}

  def wire(%__MODULE__{} = c, from, to),
    do: %{c | wires: Map.update(c.wires, from, [to], &(&1 ++ [to]))}

  def push(%__MODULE__{} = c, id, data) do
    case Step.push(Map.fetch!(c.parts, id), data) do
      {:quiet, part} ->
        {put_part(c, id, part), []}

      {:emit, out, part} ->
        c = put_part(c, id, part)

        case Map.get(c.wires, id, []) do
          [] ->
            {c, [out]}

          targets ->
            Enum.reduce(targets, {c, []}, fn to, {c, outs} ->
              {c, more} = push(c, to, out)
              {c, outs ++ more}
            end)
        end
    end
  end

  defp put_part(c, id, part), do: %{c | parts: Map.put(c.parts, id, part)}
end

defmodule Maximum do
  defstruct max: nil

  defimpl Step do
    def push(%{max: m} = s, v) when m != nil and v <= m, do: {:quiet, s}
    def push(s, v), do: {:emit, v, %{s | max: v}}
  end
end

# A sink for the LiveView paradigm: its output means "put this in assign `key`".
defmodule ToAssign do
  defstruct [:key]

  defimpl Step do
    def push(%{key: key} = s, v), do: {:emit, {:assign, key, v}, s}
  end
end
