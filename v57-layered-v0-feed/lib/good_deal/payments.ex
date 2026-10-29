defmodule GoodDeal.Payments do
  @moduledoc """
  The Payments context. The provider is configured with `config :good_deal, :payment_provider`.
  """

  def create_checkout_session(items, opts) do
    line_items =
      Enum.map(
        items,
        &%{name: &1.product.name, unit_price: &1.product.amount, quantity: &1.quantity}
      )

    provider().create_checkout_session(line_items, opts)
  end

  defp provider, do: Application.fetch_env!(:good_deal, :payment_provider)
end
