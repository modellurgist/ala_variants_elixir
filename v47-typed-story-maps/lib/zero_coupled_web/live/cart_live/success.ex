defmodule ZeroCoupledWeb.CartLive.Success do
  @moduledoc """
  Success live view displayed after checkout completion.
  """

  use ZeroCoupledWeb, :live_view

  alias ZeroCoupled.Foundation.Carts

  @impl true
  def mount(_params, session, socket) do
    cart = Carts.get(session[ZeroCoupledWeb.CartSession.cart_key()])
    {:ok, assign(socket, :cart, cart)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md rounded-2xl border border-stone-200 bg-white p-10 text-center shadow-sm">
      <div class="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-brand-100 text-brand-700">
        <.icon name="hero-check" class="h-6 w-6" />
      </div>
      <h1 class="pb-2 text-3xl font-semibold tracking-tight">You did it!</h1>
      <p class="text-stone-600">Thanks for your business!</p>
    </div>
    """
  end
end
