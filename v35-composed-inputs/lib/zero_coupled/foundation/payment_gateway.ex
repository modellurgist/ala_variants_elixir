defmodule ZeroCoupled.Foundation.PaymentGateway do
  @moduledoc """
  Foundation-layer behaviour for taking payment for a cart. An implementation
  opens a checkout session for the given line items and returns a URL to send
  the shopper to; swapping implementations (the built-in ledger, a hosted
  processor, a test double) is a one-line config change.
  """

  @type line_item :: %{
          name: String.t(),
          description: String.t(),
          image_url: String.t(),
          unit_amount: integer(),
          currency: String.t(),
          quantity: integer()
        }

  @type urls :: %{success_url: String.t(), cancel_url: String.t()}

  @callback create_checkout_session([line_item()], map(), urls()) ::
              {:ok, String.t()} | {:error, term()}
end
