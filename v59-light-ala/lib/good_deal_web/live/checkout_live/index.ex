defmodule GoodDealWeb.CheckoutLive.Index do
  use GoodDealWeb, :live_view

  alias GoodDeal.{Orders, Payments, ShoppingCart}
  alias GoodDeal.Domain.Pricing
  alias GoodDealWeb.{Calibration, CartSession}

  @impl true
  def mount(_params, session, socket) do
    parts = parts(session)
    cart = ShoppingCart.get_cart!(parts.shop.cart_id)

    {:ok,
     socket
     |> assign(
       page_title: "Checkout",
       parts: parts,
       cart: cart,
       step: nil,
       processing: false,
       payment_error: nil,
       paying_items: []
     )
     |> CartSession.guard_open_cart(parts.shop, ~p"/cart")
     |> assign_address_form()
     |> assign_summary()}
  end

  defp parts(session) do
    shop = CartSession.session_shop(session, :storefront)

    %{
      shop: shop,
      pricing: &Calibration.pricing(shop.channel, &1),
      success_url: url(~p"/cart/success")
    }
  end

  @impl true
  def handle_params(_params, _url, socket) do
    %{step: step, live_action: requested, cart: cart} = socket.assigns

    if step_allowed?(step, requested, cart) do
      {:noreply, assign(socket, :step, requested)}
    else
      {:noreply, push_patch(socket, to: step_path(step || :address))}
    end
  end

  # Moving back is always allowed; moving forward only via a valid form submit,
  # except that a fresh page load may resume at payment once an address is saved.
  defp step_allowed?(step, step, _cart), do: true
  defp step_allowed?(_step, :address, _cart), do: true
  defp step_allowed?(nil, :payment, cart), do: cart.address != nil
  defp step_allowed?(_step, _requested, _cart), do: false

  defp step_path(:address), do: ~p"/cart/checkout"
  defp step_path(:payment), do: ~p"/cart/checkout/payment"

  @impl true
  def handle_event("validate_address", %{"address" => params}, socket) do
    changeset = ShoppingCart.change_address(socket.assigns.parts.shop, params)

    {:noreply, assign(socket, :address_form, to_form(changeset, action: :validate, as: :address))}
  end

  def handle_event("save_address", %{"address" => params}, socket) do
    case ShoppingCart.save_address(socket.assigns.parts.shop, params) do
      {:ok, cart} ->
        {:noreply,
         socket
         |> assign(cart: cart, step: :payment)
         |> assign_address_form()
         |> push_patch(to: step_path(:payment))}

      {:error, changeset} ->
        {:noreply, assign(socket, :address_form, to_form(changeset, as: :address))}
    end
  end

  def handle_event("edit_address", _params, socket) do
    {:noreply, push_patch(socket, to: step_path(:address))}
  end

  def handle_event("pay", _params, socket) do
    case ShoppingCart.check_stock(socket.assigns.parts.shop) do
      {:error, :empty} ->
        {:noreply, put_flash(socket, :error, "Your cart is empty")}

      {:error, :out_of_stock} ->
        {:noreply, put_flash(socket, :error, "Some items are out of stock")}

      {:ok, items} ->
        success_url = socket.assigns.parts.success_url

        {:noreply,
         socket
         |> assign(processing: true, payment_error: nil, paying_items: items)
         |> start_async(:payment, fn ->
           Payments.create_checkout_session(items, success_url: success_url)
         end)}
    end
  end

  @impl true
  def handle_async(:payment, {:ok, {:ok, url}}, socket) do
    %{cart: cart, parts: parts, paying_items: items} = socket.assigns
    summary = Pricing.summary(parts.pricing.(cart), items)

    case Orders.complete_checkout(parts.shop, summary) do
      {:ok, _order} ->
        {:noreply, redirect(socket, external: url)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:processing, false)
         |> put_flash(:error, "Some items are out of stock")}
    end
  end

  def handle_async(:payment, _failed, socket) do
    {:noreply, assign(socket, processing: false, payment_error: "Payment failed.")}
  end

  defp assign_address_form(socket) do
    changeset = ShoppingCart.change_address(socket.assigns.parts.shop, %{})
    assign(socket, :address_form, to_form(changeset, as: :address))
  end

  defp assign_summary(socket) do
    %{cart: cart, parts: parts} = socket.assigns

    items = ShoppingCart.list_cart_items(parts.shop)
    assign(socket, :summary, Pricing.summary(parts.pricing.(cart), items))
  end
end
