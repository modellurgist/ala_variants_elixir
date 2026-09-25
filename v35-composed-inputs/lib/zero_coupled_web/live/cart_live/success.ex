defmodule ZeroCoupledWeb.CartLive.Success do
  @moduledoc """
  Success live view displayed after checkout completion.
  """

  use ZeroCoupledWeb, :live_view

  alias ZeroCoupled.Foundation.Carts

  @impl true
  def mount(_params, session, socket) do
    cart = Carts.get(session["cart_id"])
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
