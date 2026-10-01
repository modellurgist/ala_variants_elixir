defmodule GoodDeal.Foundation.LedgerGateway do
  @moduledoc """
  Default payment gateway: an in-process ledger that settles a charge
  synchronously and hands back an opaque reference. It calls no external
  service, so checkout is deterministic and the app has no payment-provider
  dependency; a real processor can be dropped in behind the same behaviour.
  """

  @behaviour GoodDeal.Foundation.PaymentGateway

  @impl true
  def charge(amount_cents, currency, _metadata)
      when is_integer(amount_cents) and amount_cents > 0 and is_binary(currency) do
    {:ok, "chg_" <> Integer.to_string(System.unique_integer([:positive]))}
  end

  def charge(_amount_cents, _currency, _metadata), do: {:error, :invalid_charge}
end
