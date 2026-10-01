defmodule GoodDeal.Features.Cart do
  @moduledoc """
  The shopper's cart: its lines, the shopper's choices (shipping tier, gift wrap, promo code), and
  what they come to. It reads and writes its lines through the `store` it is configured with.
  Every input takes the cart and a value and returns the new cart with a keyword list of port
  outputs. Ports out:

    * `:rows`     a change to the displayed lines: `{:reset, rows}` or `{:changed | :removed, row}`
    * `:summary`  what the cart comes to, and the choices behind it
    * `:removed`  the line that left
    * `:promo_applied` / `:promo_rejected`  the code, after a promo attempt
    * `:checkout_requested`  `%{cart_id, items}`, for whoever takes payment

  Nothing here names a stream, a message, or where any output goes.
  """
  alias GoodDeal.Domain.{GiftWrap, Inventory, Lines, Pricing, Promo, Shipping}

  defstruct [
    :cart_id,
    :store,
    :shipping,
    :promo,
    :gift_wrap,
    :stock,
    items: [],
    promo_code: nil,
    promo_percentage: nil,
    shipping_method: nil,
    gift_wrap?: false
  ]

  def ports,
    do: %{
      in: [
        load: :event,
        update_quantity: :event,
        remove: :event,
        select_shipping: :method,
        toggle_gift_wrap: :event,
        apply_promo: :code,
        set_stock: :stock_change,
        request_checkout: :event
      ],
      out: [
        rows: :row_change,
        summary: :summary,
        removed: :item,
        promo_applied: :code,
        promo_rejected: :code,
        checkout_requested: :order
      ]
    }

  @doc "Config: `cart_id`, `store`, and the configured rules `shipping`, `promo`, `gift_wrap`, `stock`."
  def new(opts), do: struct!(__MODULE__, opts)

  def load(%__MODULE__{} = cart, _) do
    cart = %{cart | items: cart.store.list_items(cart.cart_id)}
    {cart, [rows: {:reset, rows(cart)}, summary: summary(cart)]}
  end

  def update_quantity(%__MODULE__{} = cart, %{item_id: id, delta: delta}) do
    items = Lines.update_quantity(cart.items, id, delta)

    case Enum.find(items, &(&1.id == id)) do
      nil ->
        {cart, []}

      line ->
        cart.store.update_quantity(cart.cart_id, id, line.quantity)
        cart = %{cart | items: items}
        {cart, [rows: {:changed, row(cart, line)}, summary: summary(cart)]}
    end
  end

  def remove(%__MODULE__{} = cart, %{item_id: id}) do
    case Lines.pop(cart.items, id) do
      {nil, _} ->
        {cart, []}

      {line, rest} ->
        cart.store.remove_item(cart.cart_id, id)
        cart = %{cart | items: rest}
        {cart, [rows: {:removed, row(cart, line)}, removed: line, summary: summary(cart)]}
    end
  end

  def select_shipping(%__MODULE__{} = cart, method),
    do: reprice(%{cart | shipping_method: method})

  def toggle_gift_wrap(%__MODULE__{} = cart, _),
    do: reprice(%{cart | gift_wrap?: not cart.gift_wrap?})

  def apply_promo(%__MODULE__{} = cart, code) do
    case Promo.call(cart.promo, code) do
      {:ok, pct} ->
        {cart, outs} = reprice(%{cart | promo_code: code, promo_percentage: pct})
        {cart, outs ++ [promo_applied: code]}

      {:error, :invalid_code} ->
        {cart, [promo_rejected: code]}
    end
  end

  def set_stock(%__MODULE__{} = cart, %{product_id: product_id, stock: stock}) do
    cart = %{cart | items: Lines.set_stock(cart.items, product_id, stock)}

    case Enum.find(cart.items, &(&1.product.id == product_id)) do
      nil -> {cart, []}
      line -> {cart, [rows: {:changed, row(cart, line)}]}
    end
  end

  def request_checkout(%__MODULE__{} = cart, _),
    do: {cart, [checkout_requested: %{cart_id: cart.cart_id, items: cart.items}]}

  defp reprice(cart), do: {cart, [summary: summary(cart)]}

  # the projected value a displayed line carries: a neutral shape, never the stored struct
  defp row(%__MODULE__{} = cart, line) do
    %{
      id: line.id,
      product: %{
        name: line.product.name,
        thumbnail: line.product.thumbnail,
        amount: Money.new(line.product.amount)
      },
      quantity: line.quantity,
      at_minimum: Lines.at_minimum?(line),
      line_total: Money.new(Pricing.line_total(line.product.amount, line.quantity)),
      stock_status: Inventory.status(cart.stock, line.product.stock)
    }
  end

  defp rows(%__MODULE__{} = cart), do: Enum.map(cart.items, &row(cart, &1))

  defp summary(%__MODULE__{} = cart) do
    subtotal = Pricing.subtotal_cents(cart.items)
    {discounted, discount} = Pricing.apply_discount(subtotal, cart.promo_percentage || 0)
    count = Pricing.item_count(cart.items)
    shipping = Shipping.cost(cart.shipping, cart.shipping_method, discounted)
    gift_wrap = if cart.gift_wrap?, do: GiftWrap.total(cart.gift_wrap, count), else: 0

    %{
      empty?: cart.items == [],
      item_count: count,
      subtotal: Money.new(subtotal),
      promo_code: cart.promo_code,
      discount: Money.new(discount),
      shipping_method: cart.shipping_method,
      shipping_options: Shipping.options(cart.shipping),
      shipping: Money.new(shipping),
      gift_wrap?: cart.gift_wrap?,
      gift_wrap: Money.new(gift_wrap),
      total: Money.new(discounted + shipping + gift_wrap)
    }
  end
end
