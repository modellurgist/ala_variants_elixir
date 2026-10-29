defmodule GoodDealWeb.CartSession do
  @moduledoc """
  The session keys for each channel's cart, the `%Shop{}` a page or plug builds from one,
  and the guard that keeps a page from writing to a session cart that has since closed.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3, redirect: 2]

  alias GoodDeal.{Shop, ShoppingCart}
  alias GoodDealWeb.{Calibration, UndoRemoval}

  # The router hands these to the EnsureCart plug.
  def cart_key, do: "cart_id"

  def portal_cart_key, do: "portal_cart_id"

  # `struct!/2` raises on a missing `cart_id` or an unknown key. A new field is one more option.
  def shop(channel, overrides),
    do: struct!(Shop, [channel: Calibration.channel(channel)] ++ overrides)

  def session_shop(session, :storefront), do: shop(:storefront, cart_id: session[cart_key()])
  def session_shop(session, :portal), do: shop(:portal, cart_id: session[portal_cart_key()])

  @doc """
  The parts of a page that edits its session cart line by line (the cart page and the
  portal): the channel's shop, its pricing as a function of the cart, and deferred removal
  over the page's `stream`, repriced with the page's own `reprice`.
  """
  def editor_parts(session, channel, stream, reprice) do
    shop = session_shop(session, channel)

    %{
      shop: shop,
      pricing: &Calibration.pricing(shop.channel, &1),
      undo: %UndoRemoval{
        shop: shop,
        stream: stream,
        reprice: reprice,
        window_ms: Calibration.undo_window_ms()
      }
    }
  end

  @doc """
  Before each of the page's events (or only those named in `:only`), checks that the
  shop's cart is still open. A LiveView cannot write the session, so when the cart has
  closed (ordered in another tab, say) the page reloads `path` with a full request, where
  `Plugs.EnsureCart` resolves an open cart, and the event is dropped with a flash.
  """
  def guard_open_cart(socket, %Shop{} = shop, path, opts \\ []) do
    only = Keyword.get(opts, :only, :all)

    attach_hook(socket, :open_cart, :handle_event, fn event, _params, socket ->
      if (only != :all and event not in only) or not ShoppingCart.cart_closed?(shop) do
        {:cont, socket}
      else
        {:halt,
         socket
         |> put_flash(:error, "That cart is closed, so nothing changed. Please try again.")
         |> redirect(to: path)}
      end
    end)
  end
end
