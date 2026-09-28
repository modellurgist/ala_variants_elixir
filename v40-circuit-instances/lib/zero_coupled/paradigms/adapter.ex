defmodule ZeroCoupled.Paradigms.Adapter do
  @moduledoc """
  Makes a feature written as `fun(state, payload) :: {state, outputs}` into a Step: the input name
  is the function. Lets the feature modules stay plain functions with no knowledge of circuits.
  """
  defstruct [:module, :state]

  def new(module, state), do: %__MODULE__{module: module, state: state}

  defimpl ZeroCoupled.Ports.Step do
    def push(%{module: m, state: state} = a, {input, payload}) do
      case apply(m, input, [state, payload]) do
        {state, []} -> {:quiet, %{a | state: state}}
        {state, outputs} -> {:emit, outputs, %{a | state: state}}
      end
    end
  end
end
