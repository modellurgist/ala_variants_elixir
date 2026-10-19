defmodule GoodDealWeb.CheckoutLive.Index do
  use GoodDealWeb, :live_view

  alias GoodDeal.{Orders, Payments, ShoppingCart}
  alias GoodDeal.ShoppingCart.Pricing

  @impl true
  def mount(_params, _session, socket) do
    cart = ShoppingCart.get_cart!(socket.assigns.cart_id)

    {:ok,
     socket
     |> assign(
       page_title: "Checkout",
       cart: cart,
       step: nil,
       processing: false,
       payment_error: nil,
       paying_items: []
     )
     |> assign(:address_form, to_form(ShoppingCart.change_address(cart), as: :address))
     |> assign_summary()}
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
    changeset = ShoppingCart.change_address(socket.assigns.cart, params)
    {:noreply, assign(socket, :address_form, to_form(changeset, action: :validate, as: :address))}
  end

  def handle_event("save_address", %{"address" => params}, socket) do
    case ShoppingCart.save_address(socket.assigns.cart, params) do
      {:ok, cart} ->
        {:noreply,
         socket
         |> assign(cart: cart, step: :payment)
         |> assign(:address_form, to_form(ShoppingCart.change_address(cart), as: :address))
         |> push_patch(to: step_path(:payment))}

      {:error, changeset} ->
        {:noreply, assign(socket, :address_form, to_form(changeset, as: :address))}
    end
  end

  def handle_event("edit_address", _params, socket) do
    {:noreply, push_patch(socket, to: step_path(:address))}
  end

  def handle_event("pay", _params, socket) do
    case ShoppingCart.check_stock(socket.assigns.cart.id) do
      {:error, :empty} ->
        {:noreply, put_flash(socket, :error, "Your cart is empty")}

      {:error, :out_of_stock} ->
        {:noreply, put_flash(socket, :error, "Some items are out of stock")}

      {:ok, items} ->
        success_url = url(~p"/cart/success")

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
    case Orders.complete_checkout(socket.assigns.cart, socket.assigns.paying_items) do
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

  defp assign_summary(socket) do
    cart = socket.assigns.cart

    summary =
      Pricing.summary(ShoppingCart.list_cart_items(cart.id),
        promo_code: cart.promo_code,
        shipping_method: cart.shipping_method,
        gift_wrap: true
      )

    assign(socket, :summary, summary)
  end
end
