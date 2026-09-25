defmodule Shop.Checkout do
  @moduledoc "The checkout feature — a small pure step machine. Private struct, no peer knowledge."
  alias Shop.Outcome

  defstruct step: :cart, address: nil

  def new, do: %__MODULE__{}

  @doc "Begin checkout if the cart isn't empty (the composition passes empty?)."
  def start(%__MODULE__{} = co, empty?) do
    if empty?,
      do: {co, [Outcome.flash(:error, "Your cart is empty")]},
      else: {%{co | step: :address}, [Outcome.patch("/cart/checkout")]}
  end

  def submit_address(%__MODULE__{} = co, address) do
    if valid_address?(address),
      do: {%{co | step: :payment, address: address}, [Outcome.patch("/cart/checkout/payment")], :ok},
      else: {co, [Outcome.flash(:error, "Address incomplete")], :error}
  end

  def edit_address(%__MODULE__{} = co), do: {%{co | step: :address}, [Outcome.patch("/cart/checkout")]}
  def complete(%__MODULE__{} = co), do: {%{co | step: :done}, [Outcome.flash(:info, "Order placed")]}

  defp valid_address?(%{name: n, line1: l, city: c}) when is_binary(n) and is_binary(l) and is_binary(c),
    do: n != "" and l != "" and c != ""

  defp valid_address?(_), do: false
end
