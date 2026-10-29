defmodule GoodDeal.Payments.InProcessProvider do
  @moduledoc """
  The default provider: settles immediately and returns the shop's own success URL.
  """
  @behaviour GoodDeal.Payments.Provider

  @impl true
  def create_checkout_session(_line_items, opts) do
    {:ok, Keyword.fetch!(opts, :success_url)}
  end
end
