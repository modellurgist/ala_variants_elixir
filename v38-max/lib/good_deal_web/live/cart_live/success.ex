defmodule GoodDealWeb.CartLive.Success do
  @moduledoc """
  Success live view displayed after checkout completion.
  """

  use GoodDealWeb, :live_view

  alias GoodDeal.Foundation.Carts
  alias GoodDealWeb.CartSession

  @impl true
  def mount(_params, session, socket) do
    cart = Carts.get(CartSession.fetch(session))
    {:ok, assign(socket, :cart, cart)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 px-6 max-w-2xl mx-auto">
      <h1 class="text-4xl pb-6 font-semibold">You did it!</h1>
      <p>Thanks for your business!</p>
    </div>
    """
  end
end
