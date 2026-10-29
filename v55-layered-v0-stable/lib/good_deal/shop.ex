defmodule GoodDeal.Shop do
  @moduledoc """
  What a page holds for its session, handed to a context in one argument: the channel's
  calibration and the session's cart.
  """

  @enforce_keys [:channel]
  defstruct [:channel, :cart_id]
end
