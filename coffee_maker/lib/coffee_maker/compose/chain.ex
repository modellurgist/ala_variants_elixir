defmodule CoffeeMaker.Compose.Chain do
  @moduledoc """
  Linear composition of Steps.

  A Chain threads data through a sequence of steps. When a step emits,
  its output becomes the next step's input. When a step returns `:quiet`,
  propagation stops (the step absorbed the input — it'll emit later).

  Chains are themselves Steps, so they nest: a sub-chain can be one step
  in a larger chain. This is how you build reusable sub-assemblies.

  ## Integration with Elixir

  Chains work naturally with `Enum.reduce`, `Stream.transform`, and
  pattern matching — no special framework needed beyond this module.

      # Process a list of readings through any Step
      {outputs, step} = Chain.fold(step, readings)

      # Lazy stream processing through any Step
      stream = Chain.to_stream(input_stream, step)
  """

  alias CoffeeMaker.Compose.Step

  @type t :: %__MODULE__{steps: [Step.t()]}

  defstruct [:steps]

  @doc "Build a chain from a list of steps."
  @spec new([Step.t()]) :: t()
  def new(steps) when is_list(steps), do: %__MODULE__{steps: steps}

  @doc """
  Push one value into the chain.

  Returns `{:emit, output, chain}` if the value made it all the way
  through, or `{:quiet, chain}` if a step absorbed it.
  """
  @spec push(t(), term()) :: Step.result()
  def push(%__MODULE__{steps: steps}, data) do
    case push_through(steps, data, []) do
      {:emit, value, new_steps} -> {:emit, value, %__MODULE__{steps: new_steps}}
      {:quiet, new_steps} -> {:quiet, %__MODULE__{steps: new_steps}}
    end
  end

  @doc """
  Push many values through any Step, collecting the emitted outputs.

  Accepts a `Chain` or any other value implementing the `Step` protocol.
  Returns `{outputs, updated_step}`.
  """
  @spec fold(Step.t(), [term()]) :: {[term()], Step.t()}
  def fold(step, inputs) when is_list(inputs) do
    {outputs, step} =
      Enum.reduce(inputs, {[], step}, fn data, {outs, s} ->
        case Step.push(s, data) do
          {:emit, value, s} -> {[value | outs], s}
          {:quiet, s} -> {outs, s}
        end
      end)

    {Enum.reverse(outputs), step}
  end

  @doc """
  Turn any Step into a Stream transformer.

  Accepts a `Chain` or any other value implementing the `Step` protocol.
  """
  @spec to_stream(Enumerable.t(), Step.t()) :: Enumerable.t()
  def to_stream(input_stream, step) do
    Stream.transform(input_stream, step, fn data, s ->
      case Step.push(s, data) do
        {:emit, value, s} -> {[value], s}
        {:quiet, s} -> {[], s}
      end
    end)
  end

  @doc "Retrieve the step at a given index (0-based)."
  @spec step_at(t(), non_neg_integer()) :: Step.t() | nil
  def step_at(%__MODULE__{steps: steps}, index), do: Enum.at(steps, index)

  defp push_through([], data, acc) do
    {:emit, data, Enum.reverse(acc)}
  end

  defp push_through([step | rest], data, acc) do
    case Step.push(step, data) do
      {:emit, output, new_step} ->
        push_through(rest, output, [new_step | acc])

      {:quiet, new_step} ->
        {:quiet, Enum.reverse([new_step | acc]) ++ rest}
    end
  end
end

defimpl CoffeeMaker.Compose.Step, for: CoffeeMaker.Compose.Chain do
  def push(chain, data), do: CoffeeMaker.Compose.Chain.push(chain, data)
end
