defmodule GoodDealWeb.CheckoutMetadata do
  @moduledoc """
  The one source of the payment metadata contract: the key `CartLive.Show`
  attaches to a charge and reads back, rather than agreeing on a bare
  `"cart_id"` string in two places. The gateway carries it opaquely, so a real
  processor can echo it on its own records.
  """

  @cart_id "cart_id"

  @doc "Metadata to attach to a charge for `cart_id`."
  def for_cart(cart_id), do: %{@cart_id => cart_id}

  @doc "Read the cart id back from charge metadata."
  def cart_id(metadata), do: metadata[@cart_id]
end
