defmodule GoodDeal.Payments.Provider do
  @moduledoc """
  A payment provider opens a checkout session for some line items and returns
  the URL to send the shopper to.
  """

  @type line_item :: %{name: String.t(), unit_price: integer(), quantity: pos_integer()}

  @callback create_checkout_session([line_item()], opts :: keyword()) ::
              {:ok, url :: String.t()} | {:error, term()}
end
