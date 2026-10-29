defmodule GoodDealWeb.CheckoutLive.Success do
  use GoodDealWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Thank you")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Thank you for your order!
      <:subtitle>Your payment went through and your order is on its way.</:subtitle>
    </.header>
    <.back navigate={~p"/products"}>Keep shopping</.back>
    """
  end
end
