defmodule GoodDealWeb.CartLive.CheckoutState do
  @moduledoc false

  # step: :address | :payment | :processing | :error | :complete
  defstruct step: :address, address: nil, status: :idle
end
