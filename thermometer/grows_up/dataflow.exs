# Shared by the other scripts: the dataflow paradigm (Step, Chain) and the
# generic domain abstractions. Nothing here knows about thermometers.

defprotocol Step do
  @doc "Returns {:emit, output, step} when it has a result, {:quiet, step} when it does not."
  def push(step, data)
end

defimpl Step, for: Function do
  def push(f, data), do: {:emit, f.(data), f}
end

defmodule Chain do
  defstruct steps: []
  def new(steps), do: %__MODULE__{steps: steps}

  def run(chain, inputs) do
    Enum.reduce(inputs, chain, fn input, chain ->
      case Step.push(chain, input) do
        {:emit, _, chain} -> chain
        {:quiet, chain} -> chain
      end
    end)
  end

  defimpl Step do
    def push(%Chain{steps: steps} = chain, data), do: flow(steps, data, [], chain)

    defp flow([], data, done, chain), do: {:emit, data, %{chain | steps: Enum.reverse(done)}}

    defp flow([step | rest], data, done, chain) do
      case Step.push(step, data) do
        {:emit, out, step} -> flow(rest, out, [step | done], chain)
        {:quiet, step} -> {:quiet, %{chain | steps: Enum.reverse(done, [step | rest])}}
      end
    end
  end
end

defmodule OffsetAndScale do
  defstruct [:offset, :scale]

  defimpl Step do
    def push(%{offset: o, scale: s} = oas, v), do: {:emit, (v + o) * s, oas}
  end
end

defmodule LowPassFilter do
  defstruct [:strength, :last]

  defimpl Step do
    def push(%{strength: k, last: last} = f, v) do
      out = last + (v - last) / k
      {:emit, out, %{f | last: out}}
    end
  end
end

defmodule SampleEvery do
  defstruct [:n, count: 0]

  defimpl Step do
    def push(%{n: n, count: c} = s, v) when c + 1 >= n, do: {:emit, v, %{s | count: 0}}
    def push(%{count: c} = s, _v), do: {:quiet, %{s | count: c + 1}}
  end
end

defmodule NumberToString do
  defstruct decimals: 1

  defimpl Step do
    def push(%{decimals: d} = f, v), do: {:emit, :erlang.float_to_binary(v / 1, decimals: d), f}
  end
end

defmodule Display do
  defstruct label: ""

  defimpl Step do
    def push(%{label: label} = d, text) do
      IO.puts("#{label}#{text}")
      {:emit, text, d}
    end
  end
end

