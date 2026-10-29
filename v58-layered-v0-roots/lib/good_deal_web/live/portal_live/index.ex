defmodule GoodDealWeb.PortalLive.Index do
  use GoodDealWeb, :live_view

  alias GoodDeal.{Catalog, Orders, ProductEvents, ShoppingCart}
  alias GoodDeal.Domain.{Pricing, StockStatus}
  alias GoodDealWeb.{Calibration, CartSession, UndoRemoval}

  @impl true
  def mount(_params, session, socket) do
    %{shop: shop} = parts = parts(session)

    case ShoppingCart.get_cart!(shop.cart_id) do
      %{status: :open} = cart ->
        if connected?(socket), do: ProductEvents.subscribe()

        {:ok,
         socket
         |> assign(
           page_title: "B2B portal",
           parts: parts,
           cart: cart,
           step: nil,
           order: nil,
           po_form: to_form(Orders.change_purchase_order(shop), as: :po)
         )
         |> UndoRemoval.init()
         |> stream(:products, Catalog.list_products())
         |> stream(:lines, ShoppingCart.list_cart_items(shop))
         |> assign_summary()}

      # Live navigation reuses the session of the page that submitted the draft;
      # a full request lets the session plug start a new draft.
      _completed ->
        {:ok, redirect(socket, to: ~p"/portal")}
    end
  end

  defp parts(session) do
    shop = CartSession.session_shop(session, :portal)

    %{
      shop: shop,
      pricing: &Calibration.pricing(shop.channel, &1),
      undo: %UndoRemoval{stream: :lines, window_ms: Calibration.undo_window_ms()}
    }
  end

  @impl true
  def handle_params(_params, _url, socket) do
    %{step: step, live_action: requested} = socket.assigns

    if step_allowed?(step, requested, socket) do
      {:noreply, assign(socket, :step, requested)}
    else
      {:noreply, push_patch(socket, to: step_path(step || :order))}
    end
  end

  defp step_allowed?(step, step, _socket), do: true
  defp step_allowed?(step, :order, _socket) when step in [nil, :review], do: true
  defp step_allowed?(nil, :review, socket), do: socket.assigns.summary.item_count > 0
  defp step_allowed?(_step, _requested, _socket), do: false

  defp step_path(:order), do: ~p"/portal"
  defp step_path(:review), do: ~p"/portal/review"
  defp step_path(:submitted), do: ~p"/portal/submitted"

  @impl true
  def handle_event("add_to_order", %{"product_id" => product_id, "quantity" => quantity}, socket) do
    product = Catalog.get_product!(product_id)
    socket = UndoRemoval.finalize(socket)

    {:ok, item} =
      ShoppingCart.add_item(
        socket.assigns.parts.shop,
        product.id,
        max(parse_quantity(quantity), 1)
      )

    {:noreply,
     socket
     |> stream_insert(:lines, item)
     |> put_flash(:info, "Added to order")
     |> assign_summary()}
  end

  def handle_event("update_line", %{"item_id" => id, "quantity" => quantity}, socket) do
    case parse_quantity(quantity) do
      quantity when quantity >= 1 ->
        {:ok, item} = ShoppingCart.update_item(get_item(socket, id), %{quantity: quantity})
        {:noreply, socket |> stream_insert(:lines, item) |> assign_summary()}

      _invalid ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_line", %{"item-id" => id}, socket) do
    {:noreply,
     socket
     |> UndoRemoval.remove(socket.assigns.parts.undo, get_item(socket, id))
     |> assign_summary()}
  end

  def handle_event("undo_remove", _params, socket) do
    {:noreply, socket |> UndoRemoval.undo(socket.assigns.parts.undo) |> assign_summary()}
  end

  def handle_event("select_shipping", %{"method" => method}, socket) do
    {:ok, cart} = ShoppingCart.select_shipping_method(socket.assigns.parts.shop, method)

    {:noreply, socket |> assign(:cart, cart) |> assign_summary()}
  end

  def handle_event("review", _params, socket) do
    socket = UndoRemoval.finalize(socket)

    if socket.assigns.summary.item_count == 0 do
      {:noreply, put_flash(socket, :error, "Your order is empty")}
    else
      {:noreply, socket |> assign(:step, :review) |> push_patch(to: step_path(:review))}
    end
  end

  def handle_event("edit_lines", _params, socket) do
    {:noreply, push_patch(socket, to: step_path(:order))}
  end

  def handle_event("validate_po", %{"po" => params}, socket) do
    changeset = Orders.change_purchase_order(socket.assigns.parts.shop, params)
    {:noreply, assign(socket, :po_form, to_form(changeset, action: :validate, as: :po))}
  end

  def handle_event("submit_order", %{"po" => params}, socket) do
    %{cart: cart, parts: parts} = socket.assigns
    items = ShoppingCart.list_cart_items(parts.shop)
    summary = Pricing.summary(parts.pricing.(cart), items)

    case Orders.submit_portal_order(parts.shop, summary, params) do
      {:ok, order} ->
        {:noreply,
         socket
         |> assign(order: order, step: :submitted)
         |> put_flash(:info, "Order submitted")
         |> push_patch(to: step_path(:submitted))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :po_form, to_form(changeset, as: :po))}
    end
  end

  @impl true
  def handle_info({:undo_expired, item_id}, socket) do
    {:noreply, UndoRemoval.expire(socket, item_id)}
  end

  def handle_info({:product_created, product}, socket) do
    {:noreply, stream_insert(socket, :products, product)}
  end

  def handle_info({:product_updated, product}, socket) do
    socket = stream_insert(socket, :products, product)

    if MapSet.member?(socket.assigns.line_product_ids, product.id) do
      item = ShoppingCart.get_cart_item_for_product(socket.assigns.parts.shop, product.id)
      {:noreply, socket |> stream_insert(:lines, item) |> assign_summary()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:product_deleted, product}, socket) do
    socket = stream_delete(socket, :products, product)

    if MapSet.member?(socket.assigns.line_product_ids, product.id) do
      {:noreply, socket |> stream(:lines, visible_items(socket), reset: true) |> assign_summary()}
    else
      {:noreply, socket}
    end
  end

  defp get_item(socket, id), do: ShoppingCart.get_cart_item!(socket.assigns.parts.shop, id)

  defp parse_quantity(value) do
    case Integer.parse(to_string(value)) do
      {quantity, ""} -> quantity
      _ -> 0
    end
  end

  defp visible_items(socket) do
    pending_id = UndoRemoval.pending_id(socket)

    socket.assigns.parts.shop
    |> ShoppingCart.list_cart_items()
    |> Enum.reject(&(&1.id == pending_id))
  end

  # Product broadcasts are store-wide; line_product_ids lets handlers skip unrelated products.
  defp assign_summary(socket) do
    items = visible_items(socket)

    %{cart: cart, parts: parts} = socket.assigns
    summary = Pricing.summary(parts.pricing.(cart), items)
    assign(socket, summary: summary, line_product_ids: MapSet.new(items, & &1.product_id))
  end
end
