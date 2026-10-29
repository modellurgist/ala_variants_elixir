defmodule GoodDeal.Shop do
  @moduledoc """
  What a page holds for its session, handed to a context in one argument: the channel's
  calibration and the session's cart. `cart_id` is enforced but may be nil, which only
  `ShoppingCart.get_or_create_open_cart/1` accepts, as "no cart yet".
  """

  @enforce_keys [:channel, :cart_id]
  defstruct @enforce_keys
end
