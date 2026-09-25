defprotocol CoffeeMaker.Compose.Step do
  @moduledoc """
  The unit of ALA abstraction in Elixir.

  A Step receives data and either emits a transformed value or stays quiet
  (absorbing the input for later, like a filter or down-sampler).

  ## Returns

    - `{:emit, output, updated_step}` — produced a value
    - `{:quiet, updated_step}` — absorbed the input, no output

  ## What qualifies as a Step

    - **A plain function** — `fn x -> x * 2 end` is a valid step (always emits)
    - **A struct with `defimpl Step`** — for stateful transforms
    - **A Chain** — chains are steps too, enabling fractal composition
    - **A Stateful wrapper** — turn any `(data, state) -> result` function
      into a step without defining a module

  This protocol is the Elixir equivalent of ALA's programming paradigm
  interface (like C#'s `IDataFlow<T>`), but simplified to a single function.
  """

  @type result :: {:emit, term(), t()} | {:quiet, t()}

  @doc "Push data into the step. Returns `{:emit, output, new_step}` or `{:quiet, new_step}`."
  @spec push(t(), term()) :: result()
  def push(step, data)
end

defimpl CoffeeMaker.Compose.Step, for: Function do
  def push(fun, data), do: {:emit, fun.(data), fun}
end
