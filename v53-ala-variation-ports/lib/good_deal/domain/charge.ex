defmodule GoodDeal.Domain.Charge do
  @moduledoc """
  Charges for a cart's line items through the payment gateway it is configured with. Config:
  `gateway` (a `PaymentGateway`) and `metadata` (a function of the cart id giving what the charge
  carries). Called with `{line_items, cart_id}`; answers what the gateway answers.
  """
  defstruct [:gateway, :metadata]

  def call(%__MODULE__{gateway: gateway, metadata: metadata}, {[first | _] = line_items, cart_id}) do
    amount = line_items |> Enum.map(&(&1.unit_amount * &1.quantity)) |> Enum.sum()
    gateway.charge(amount, first.currency, metadata.(cart_id))
  end
end
