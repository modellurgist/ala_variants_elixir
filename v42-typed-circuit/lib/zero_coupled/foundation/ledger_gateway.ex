defmodule ZeroCoupled.Foundation.LedgerGateway do
  @moduledoc """
  Default payment gateway: settles the charge in-process and hands back the
  app's own success URL to advance to. It calls no external provider, so
  checkout is deterministic and the app carries no payment-SDK dependency; a
  hosted processor can be dropped in behind the same behaviour.
  """

  @behaviour ZeroCoupled.Foundation.PaymentGateway

  @impl true
  def create_checkout_session(_line_items, _metadata, %{success_url: success_url}),
    do: {:ok, success_url}
end
