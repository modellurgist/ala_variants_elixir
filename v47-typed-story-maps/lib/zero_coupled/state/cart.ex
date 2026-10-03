defmodule ZeroCoupled.State.Cart do
  @moduledoc """
  The shopper's cart as a feature: the `ZeroCoupled.Cart` aggregate plus the ports it speaks
  through. Every step takes the cart and an input, and returns the new cart with a keyword list of
  port outputs. Ports out:

    * `:rows`     a change to the displayed lines: `{:added | :changed | :removed, row}`
    * `:summary`  the pricing summary (item count, subtotal, discount, gift wrap, shipping, total)
    * `:removed`  the line that left (so something can offer to bring it back)
    * `:saved`    the line set aside for later
    * `:changed`  what changed in a stored line: `{:quantity, cart_id, item_id, qty}` or `{:removed, cart_id, item_id}`
    * `:promo_applied` / `:promo_rejected`  the code, after a promo attempt

  Nothing here names a stream, a message, or where any output goes.
  """
  alias ZeroCoupled.Cart
  alias ZeroCoupled.Domain.{CalculateShipping, StockStatus}

  @type t :: Cart.t()

  def ports,
    do: %{
      in: [
        load: :items,
        line: :event,
        start_checkout: :event,
        request_checkout: :event,
        update_quantity: :event,
        remove: :event,
        receive: :item,
        confirm_removal: :item_id,
        save_for_later: :event,
        toggle_gift_wrap: :event,
        select_shipping: :event,
        apply_promo: :event,
        set_stock: :stock_change
      ],
      out: [
        rows: :row_change,
        summary: :summary,
        removed: :item,
        saved: :item,
        line: :line,
        changed: :cart_change,
        promo_applied: :code,
        promo_rejected: :code,
        checkout_started: :summary,
        checkout_requested: :checkout_request
      ]
    }

  @doc "The shopper wants to check out: the cart's summary goes out for whoever runs checkout."
  def start_checkout(%Cart{} = cart, _), do: {cart, [checkout_started: summary(cart)]}

  @doc "The shopper wants to pay: the cart's id and stored lines go out, not the cart itself."
  def request_checkout(%Cart{} = cart, _),
    do: {cart, [checkout_requested: {Cart.id(cart), Cart.items(cart)}]}

  @doc "The persisted lines arrive: the whole display resets to them."
  def load(%Cart{} = cart, items) do
    cart = Cart.new(cart_id: cart.cart_id, items: items, pricing: cart.pricing)
    {cart, [rows: {:reset, rows(cart)}, summary: summary(cart)]}
  end

  @doc "Hand a line out (to whoever the page wires it to: the wishlist, say)."
  def line(%Cart{} = cart, %{item_id: item_id}), do: {cart, [line: find(cart, item_id)]}

  def items(%Cart{items: items}), do: items
  def find(%Cart{items: items}, item_id), do: Enum.find(items, &(&1.id == item_id))

  def update_quantity(%Cart{} = cart, %{item_id: item_id, delta: delta}) do
    case Cart.update_quantity(cart, item_id, delta) do
      {:ok, cart, item} ->
        {cart,
         [
           rows: {:changed, row(cart, item)},
           summary: summary(cart),
           changed: {:quantity, cart.cart_id, item_id, item.quantity}
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
    do: {cart, [changed: {:removed, cart.cart_id, item_id}]}

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
      stock_status: StockStatus.call(cart.pricing.stock_status, item.product.stock),
      quantity: item.quantity,
      line_total: Money.new(item.product.amount * item.quantity),
      gift_wrapped: Cart.gift_wrapped?(cart, item.id)
    }
  end

  def rows(%Cart{} = cart), do: Enum.map(cart.items, &row(cart, &1))

  def summary(%Cart{} = cart) do
    %{
      empty?: Cart.empty?(cart),
      item_count: cart.item_count,
      subtotal: cart.subtotal,
      discount: cart.discount,
      promo_code: cart.promo_code,
      gift_wrap_total: cart.gift_wrap_total,
      shipping_method: cart.shipping_method,
      shipping_label: CalculateShipping.label(cart.pricing.shipping, cart.shipping_method),
      shipping_cost: cart.shipping_cost,
      shipping_options:
        for rate <- CalculateShipping.options(cart.pricing.shipping) do
          %{
            method: rate.method,
            label: rate.label,
            cost: Money.new(rate.cost),
            free_above: rate.free_above && Money.new(rate.free_above)
          }
        end,
      total: cart.total
    }
  end
end
