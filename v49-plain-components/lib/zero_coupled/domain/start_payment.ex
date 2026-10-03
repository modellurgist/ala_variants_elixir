defmodule ZeroCoupled.Domain.StartPayment do
  @moduledoc """
  Starts a hosted payment for a cart's line items through the gateway it is configured with.
  Config: `gateway`, the return `urls`, and `cart_key` (how the payment's metadata names the cart).
  Given `{line_items, cart_id}`, answers what the gateway answers.
  """
  defstruct [:gateway, :urls, :cart_key]

  def call(%__MODULE__{gateway: gateway, urls: urls, cart_key: key}, {line_items, cart_id}),
    do: gateway.create_checkout_session(line_items, %{key => cart_id}, urls)
end
