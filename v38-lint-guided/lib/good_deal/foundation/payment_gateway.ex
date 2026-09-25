defmodule GoodDeal.Foundation.PaymentGateway do
  @moduledoc """
  Foundation-layer behaviour for taking payment for a cart. An implementation
  settles a charge for a given amount and returns an opaque reference the
  application can record against the order. Swapping the implementation (a real
  processor, a test double, the built-in ledger) is a one-line config change.
  """

  @callback charge(amount_cents :: integer(), currency :: String.t(), metadata :: map()) ::
              {:ok, reference :: String.t()} | {:error, term()}
end
