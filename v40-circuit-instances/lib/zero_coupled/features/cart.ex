defmodule ZeroCoupled.Features.Cart do
  @moduledoc """
  The shopper's cart as a feature: the `ZeroCoupled.Cart` aggregate plus the ports it speaks
  through. Every step takes the cart and an input, and returns the new cart with a keyword list of
  port outputs. Ports out:

    * `:rows`     a change to the displayed lines: `{:added | :changed | :removed, row}`
    * `:summary`  the pricing summary (item count, subtotal, discount, gift wrap, shipping, total)
    * `:removed`  the line that left (so something can offer to bring it back)
    * `:saved`    the line set aside for later
    * `:persist`  a change to write: `{:quantity, cart_id, item_id, qty}` or `{:remove, cart_id, item_id}`
    * `:promo_applied` / `:promo_rejected`  the code, after a promo attempt

  Nothing here names a stream, a message, or where any output goes.
  """
  alias ZeroCoupled.Cart
  alias ZeroCoupled.Domain.{ShippingInfo, StockStatus}

  @type t :: Cart.t()

  def new(opts),
    do:
      Cart.new(
        cart_id: opts[:cart_id],
        items: opts[:items] || [],
        config: Map.new(opts[:pricing] || [])
      )

  @doc "The persisted lines arrive: the whole display resets to them."
  def load(%Cart{} = cart, items) do
    cart = Cart.new(cart_id: cart.cart_id, items: items, config: cart.config)
    {cart, [rows: {:reset, rows(cart)}, summary: summary(cart)]}
  end

  @doc "Hand a line out (to whoever the page wires it to: the wishlist, say)."
  def line(%Cart{} = cart, %{item_id: item_id}), do: {cart, [line: find(cart, item_id)]}

  @doc "The shopper wants to pay: the aggregate goes out for someone to check and charge."
  def request_checkout(%Cart{} = cart, _), do: {cart, [checkout_requested: cart]}

  def items(%Cart{items: items}), do: items
  def find(%Cart{items: items}, item_id), do: Enum.find(items, &(&1.id == item_id))

  def update_quantity(%Cart{} = cart, %{item_id: item_id, delta: delta}) do
    case Cart.update_quantity(cart, item_id, delta) do
      {:ok, cart, item} ->
        {cart,
         [
           rows: {:changed, row(cart, item)},
           summary: summary(cart),
           persist: {:quantity, cart.cart_id, item_id, item.quantity}
         ]}

      :error ->
        {cart, []}
    end
  end

  def remove(%Cart{} = cart, %{item_id: item_id}) do
    case Cart.remove_item(cart, item_id) do
      {:ok, cart, item} ->
        {cart, [rows: {:removed, row(cart, item)}, removed: item, summary: summary(cart)]}

      :error ->
        {cart, []}
    end
  end

  @doc "A line comes (back) into the cart: an undone removal, a saved item, a wishlisted product."
  def receive(%Cart{} = cart, item) do
    {:ok, cart, item} = Cart.add_item(cart, item)
    {cart, [rows: {:added, row(cart, item)}, summary: summary(cart)]}
  end

  @doc "A removal is final: write it."
  def confirm_removal(%Cart{} = cart, item_id),
    do: {cart, [persist: {:remove, cart.cart_id, item_id}]}

  def save_for_later(%Cart{} = cart, %{item_id: item_id}) do
    case Cart.remove_item(cart, item_id) do
      {:ok, cart, item} ->
        {cart, [rows: {:removed, row(cart, item)}, saved: item, summary: summary(cart)]}

      :error ->
        {cart, []}
    end
  end

  def toggle_gift_wrap(%Cart{} = cart, %{item_id: item_id}) do
    case Cart.toggle_gift_wrap(cart, item_id) do
      {:ok, cart, item, _wrapped?} ->
        {cart, [rows: {:changed, row(cart, item)}, summary: summary(cart)]}

      :error ->
        {cart, []}
    end
  end

  def select_shipping(%Cart{} = cart, %{method: method}) do
    cart = Cart.select_shipping(cart, method)
    {cart, [summary: summary(cart)]}
  end

  def apply_promo(%Cart{} = cart, %{code: code}) do
    case Cart.apply_promo(cart, code) do
      {:ok, cart} -> {cart, [summary: summary(cart), promo_applied: cart.promo_code]}
      {:error, :invalid_code} -> {cart, [promo_rejected: code]}
    end
  end

  def set_stock(%Cart{} = cart, %{product_id: product_id, stock: stock}) do
    case Cart.set_stock(cart, product_id, stock) do
      {:ok, cart, item} -> {cart, [rows: {:changed, row(cart, item)}]}
      :none -> {cart, []}
    end
  end

  @doc "The projected value a displayed line carries: a neutral shape, never the item struct."
  def row(%Cart{} = cart, item) do
    %{
      id: item.id,
      product_id: item.product.id,
      product: %{
        thumbnail: item.product.thumbnail,
        name: item.product.name,
        amount: item.product.amount
      },
      stock_status: StockStatus.call(item.product.stock),
      quantity: item.quantity,
      line_total: Money.new(item.product.amount * item.quantity),
      gift_wrapped: Cart.gift_wrapped?(cart, item.id)
    }
  end

  def rows(%Cart{} = cart), do: Enum.map(cart.items, &row(cart, &1))

  def summary(%Cart{} = cart) do
    rates = cart.config[:shipping] || %{}

    %{
      empty?: Cart.empty?(cart),
      item_count: cart.item_count,
      subtotal: cart.subtotal,
      discount: cart.discount,
      promo_code: cart.promo_code,
      gift_wrap_total: cart.gift_wrap_total,
      shipping_method: cart.shipping_method,
      shipping_label: (rates[cart.shipping_method] || %{})[:label],
      shipping_cost: cart.shipping_cost,
      shipping_options:
        for method <- ShippingInfo.method_names(rates), rate = rates[method] do
          %{
            method: method,
            label: rate.label,
            price_label:
              if(rate.free_above,
                do: "free over #{Money.new(rate.free_above)}",
                else: to_string(Money.new(rate.cost))
              )
          }
        end,
      total: cart.total
    }
  end
end
