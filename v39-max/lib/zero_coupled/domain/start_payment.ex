defmodule ZeroCoupled.Domain.StartPayment do
  @moduledoc """
  Starts a hosted payment for a cart's line items, doing its own I/O through the gateway it is
  configured with. Config: `gateway`, the return `urls`, and `cart_key` (how the payment's metadata
  names the cart). Called with `{line_items, cart_id}`; answers what the gateway answers.
  """
  defstruct [:gateway, :urls, :cart_key]

  defimpl ZeroCoupled.Ports.Call do
    def call(%{gateway: gateway, urls: urls, cart_key: key}, {line_items, cart_id}),
      do: gateway.create_checkout_session(line_items, %{key => cart_id}, urls)
  end
end
