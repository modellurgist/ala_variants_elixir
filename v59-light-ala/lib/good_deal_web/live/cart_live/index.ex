defmodule GoodDealWeb.CartLive.Index do
  use GoodDealWeb, :live_view

  alias GoodDeal.{Catalog, ProductEvents, ShoppingCart}
  alias GoodDeal.Domain.Pricing
  alias GoodDealWeb.{CartSession, UndoRemoval}

  @tabs ~w(items saved wishlist)

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: ProductEvents.subscribe()

    %{shop: shop} = parts = parts(session)
    cart = ShoppingCart.get_cart!(shop.cart_id)
    wishlist = ShoppingCart.list_wishlist(shop)

    {:ok,
     socket
     |> assign(
       page_title: "Your Cart",
       parts: parts,
       cart: cart,
       tab: "items",
       promo_error: nil,
       wishlisted: MapSet.new(wishlist, & &1.id)
     )
     |> CartSession.guard_open_cart(shop, ~p"/cart")
     |> UndoRemoval.init()
     |> stream(:items, ShoppingCart.list_cart_items(shop))
     |> stream(:saved, ShoppingCart.list_saved_items(shop))
     |> stream(:wishlist, wishlist)
     |> assign_summary()}
  end

  defp parts(session),
    do: CartSession.editor_parts(session, :storefront, :items, &assign_summary/1)

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @tabs do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("update_quantity", %{"item-id" => id, "delta" => delta}, socket) do
    {:ok, item} = ShoppingCart.change_quantity(get_item(socket, id), String.to_integer(delta))
    {:noreply, socket |> stream_insert(:items, item) |> assign_summary()}
  end

  def handle_event("toggle_gift_wrap", %{"item-id" => id}, socket) do
    {:ok, item} = ShoppingCart.toggle_gift_wrap(get_item(socket, id))
    {:noreply, socket |> stream_insert(:items, item) |> assign_summary()}
  end

  def handle_event("remove_item", %{"item-id" => id}, socket) do
    {:noreply, UndoRemoval.remove(socket, socket.assigns.parts.undo, id)}
  end

  def handle_event("undo_remove", _params, socket) do
    {:noreply, UndoRemoval.undo(socket, socket.assigns.parts.undo)}
  end

  def handle_event("save_for_later", %{"item-id" => id}, socket) do
    {:ok, item} = ShoppingCart.save_for_later(get_item(socket, id))

    {:noreply,
     socket
     |> stream_delete(:items, item)
     |> stream_insert(:saved, item)
     |> put_flash(:info, "Saved for later")
     |> assign_summary()}
  end

  def handle_event("move_to_cart", %{"item-id" => id}, socket) do
    {:ok, item} = ShoppingCart.move_to_cart(get_item(socket, id))

    {:noreply,
     socket
     |> stream_delete(:saved, item)
     |> stream_insert(:items, item)
     |> put_flash(:info, "Moved to cart")
     |> assign_summary()}
  end

  def handle_event("toggle_wishlist", %{"item-id" => id}, socket) do
    item = get_item(socket, id)

    socket =
      case ShoppingCart.toggle_wishlist(socket.assigns.parts.shop, item.product_id) do
        :added ->
          socket
          |> update(:wishlisted, &MapSet.put(&1, item.product_id))
          |> stream_insert(:wishlist, item.product)
          |> put_flash(:info, "Added to wishlist")

        :removed ->
          socket
          |> update(:wishlisted, &MapSet.delete(&1, item.product_id))
          |> stream_delete(:wishlist, item.product)
          |> put_flash(:info, "Removed from wishlist")
      end

    {:noreply, stream_insert(socket, :items, item)}
  end

  def handle_event("remove_from_wishlist", %{"product-id" => product_id}, socket) do
    product = Catalog.get_product!(product_id)
    :ok = ShoppingCart.remove_from_wishlist(socket.assigns.parts.shop, product.id)

    {:noreply,
     socket
     |> update(:wishlisted, &MapSet.delete(&1, product.id))
     |> stream_delete(:wishlist, product)
     |> refresh_cart_row(product.id)}
  end

  def handle_event("add_wishlisted_to_cart", %{"product-id" => product_id}, socket) do
    product = Catalog.get_product!(product_id)
    {:ok, item} = ShoppingCart.move_wishlist_item_to_cart(socket.assigns.parts.shop, product.id)

    {:noreply,
     socket
     |> update(:wishlisted, &MapSet.delete(&1, product.id))
     |> stream_delete(:wishlist, product)
     |> stream_delete(:saved, item)
     |> stream_insert(:items, item)
     |> put_flash(:info, "Added to cart")
     |> assign_summary()}
  end

  def handle_event("apply_promo", %{"code" => code}, socket) do
    case ShoppingCart.apply_promo_code(socket.assigns.parts.shop, code) do
      {:ok, cart} ->
        {:noreply,
         socket
         |> assign(cart: cart, promo_error: nil)
         |> put_flash(:info, "Promo applied!")
         |> assign_summary()}

      {:error, :invalid_promo_code} ->
        {:noreply,
         socket
         |> assign(:promo_error, "Invalid promo code")
         |> put_flash(:error, "Invalid promo code")}
    end
  end

  def handle_event("select_shipping", %{"method" => method}, socket) do
    {:ok, cart} = ShoppingCart.select_shipping_method(socket.assigns.parts.shop, method)

    {:noreply, socket |> assign(:cart, cart) |> assign_summary()}
  end

  def handle_event("checkout", _params, socket) do
    socket = UndoRemoval.finalize(socket)

    if socket.assigns.summary.item_count == 0 do
      {:noreply, put_flash(socket, :error, "Your cart is empty")}
    else
      {:noreply, push_navigate(socket, to: ~p"/cart/checkout")}
    end
  end

  @impl true
  def handle_info({:undo_expired, item_id}, socket) do
    {:noreply, UndoRemoval.expire(socket, item_id)}
  end

  def handle_info({event, product}, socket)
      when event in [:product_updated, :product_deleted] do
    if shown?(socket, product.id) do
      handle_product_change(event, product, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_info({:product_created, _product}, socket), do: {:noreply, socket}

  defp handle_product_change(:product_updated, product, socket) do
    socket =
      if MapSet.member?(socket.assigns.wishlisted, product.id),
        do: stream_insert(socket, :wishlist, product),
        else: socket

    {:noreply, socket |> refresh_cart_row(product.id) |> assign_summary()}
  end

  defp handle_product_change(:product_deleted, _product, socket) do
    shop = socket.assigns.parts.shop
    wishlist = ShoppingCart.list_wishlist(shop)

    {:noreply,
     socket
     |> assign(:wishlisted, MapSet.new(wishlist, & &1.id))
     |> stream(:items, visible_items(socket), reset: true)
     |> stream(:saved, ShoppingCart.list_saved_items(shop), reset: true)
     |> stream(:wishlist, wishlist, reset: true)
     |> assign_summary()}
  end

  # Product broadcasts are store-wide; only touch the database for products this page shows.
  defp shown?(socket, product_id) do
    MapSet.member?(socket.assigns.product_ids, product_id) or
      MapSet.member?(socket.assigns.wishlisted, product_id)
  end

  defp get_item(socket, id), do: ShoppingCart.get_cart_item!(socket.assigns.parts.shop, id)

  defp visible_items(socket) do
    pending_id = UndoRemoval.pending_id(socket)

    socket.assigns.parts.shop
    |> ShoppingCart.list_cart_items()
    |> Enum.reject(&(&1.id == pending_id))
  end

  defp refresh_cart_row(socket, product_id) do
    pending_id = UndoRemoval.pending_id(socket)

    case ShoppingCart.get_cart_item_for_product(socket.assigns.parts.shop, product_id) do
      nil -> socket
      %{id: ^pending_id} -> socket
      %{saved_for_later: true} = item -> stream_insert(socket, :saved, item)
      item -> stream_insert(socket, :items, item)
    end
  end

  defp assign_summary(socket) do
    %{cart: cart, parts: parts} = socket.assigns

    items = visible_items(socket)
    saved = ShoppingCart.list_saved_items(parts.shop)

    assign(socket,
      summary: Pricing.summary(parts.pricing.(cart), items),
      saved_count: length(saved),
      product_ids: MapSet.new(items ++ saved, & &1.product_id)
    )
  end
end
