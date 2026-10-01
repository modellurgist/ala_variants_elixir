defmodule ZeroCoupled.Features.OrderLines do
  @moduledoc """
  A bulk order's lines: the same `ZeroCoupled.Cart` aggregate the storefront uses, priced by
  volume tier instead of promo code, with absolute quantities. Ports out: `:rows`, `:summary`,
  `:removed`, `:changed`, as for the cart.
  """
  alias ZeroCoupled.Cart
  alias ZeroCoupled.Domain.{CalculateShipping, StockStatus, VolumeTier}

  def ports,
    do: %{
      in: [
        load: :items,
        set_quantity: :event,
        add: :item_quantity,
        remove: :event,
        receive: :item,
        confirm_removal: :item_id,
        set_stock: :stock_change,
        request_review: :event
      ],
      out: [
        rows: :row_change,
        summary: :summary,
        removed: :item,
        changed: :cart_change,
        review: :summary
      ]
    }

  @doc "Config: `cart_id`, `items`, and the pricing instances the composition built once (`shipping`, `volume`)."
  def new(opts),
    do:
      reprice(
        Cart.new(cart_id: opts[:cart_id], items: opts[:items] || [], pricing: opts[:pricing])
      )

  def find(%Cart{items: items}, item_id), do: Enum.find(items, &(&1.id == item_id))

  def find_by_product(%Cart{items: items}, product_id),
    do: Enum.find(items, &(&1.product.id == product_id))

  @doc "The buyer wants to review the order: its summary goes out."
  def request_review(%Cart{} = order, _), do: {order, [review: summary(order)]}

  def load(%Cart{} = order, items) do
    order = reprice(Cart.new(cart_id: order.cart_id, items: items, pricing: order.pricing))
    {order, [rows: {:reset, rows(order)}, summary: summary(order)]}
  end

  @doc "Set a line to an absolute quantity (never below 1)."
  def set_quantity(%Cart{} = order, %{item_id: item_id, quantity: quantity}) do
    with %{quantity: current} <- find(order, item_id),
         {:ok, order, line} <- Cart.update_quantity(order, item_id, max(quantity, 1) - current) do
      order = reprice(order)

      {order,
       [
         rows: {:changed, row(order, line)},
         summary: summary(order),
         changed: {:quantity, order.cart_id, item_id, line.quantity}
       ]}
    else
      _ -> {order, []}
    end
  end

  @doc "A persisted line joins the order at the requested quantity; a line already there grows by it."
  def add(%Cart{} = order, {item, quantity}) do
    already = find(order, item.id)
    {:ok, order, _} = Cart.add_item(order, item)
    target = if already, do: already.quantity + quantity, else: max(quantity, 1)

    {:ok, order, line} =
      Cart.update_quantity(order, item.id, target - find(order, item.id).quantity)

    order = reprice(order)

    {order,
     [
       rows: {:added, row(order, line)},
       summary: summary(order),
       changed: {:quantity, order.cart_id, line.id, line.quantity}
     ]}
  end

  def remove(%Cart{} = order, %{item_id: item_id}) do
    case Cart.remove_item(order, item_id) do
      {:ok, order, line} ->
        order = reprice(order)
        {order, [rows: {:removed, row(order, line)}, removed: line, summary: summary(order)]}

      :error ->
        {order, []}
    end
  end

  def receive(%Cart{} = order, item) do
    {:ok, order, line} = Cart.add_item(order, item)
    order = reprice(order)
    {order, [rows: {:added, row(order, line)}, summary: summary(order)]}
  end

  def confirm_removal(%Cart{} = order, item_id),
    do: {order, [changed: {:removed, order.cart_id, item_id}]}

  def set_stock(%Cart{} = order, %{product_id: product_id, stock: stock}) do
    case Cart.set_stock(order, product_id, stock) do
      {:ok, order, line} -> {order, [rows: {:changed, row(order, line)}]}
      :none -> {order, []}
    end
  end

  defp reprice(%Cart{} = order) do
    {pct, _label} = VolumeTier.call(order.pricing.volume, order.subtotal.amount)
    Cart.set_discount(order, pct)
  end

  def row(%Cart{} = order, line) do
    %{
      id: line.id,
      product: %{
        thumbnail: line.product.thumbnail,
        name: line.product.name,
        amount: line.product.amount
      },
      stock_status: StockStatus.call(order.pricing.stock_status, line.product.stock),
      quantity: line.quantity,
      line_total: Money.new(line.product.amount * line.quantity)
    }
  end

  def rows(%Cart{items: items} = order), do: Enum.map(items, &row(order, &1))

  def summary(%Cart{} = order) do
    {_pct, tier_label} = VolumeTier.call(order.pricing.volume, order.subtotal.amount)

    %{
      empty?: Cart.empty?(order),
      item_count: order.item_count,
      subtotal: order.subtotal,
      discount: order.discount,
      tier_label: tier_label,
      shipping_label: CalculateShipping.label(order.pricing.shipping, order.shipping_method),
      shipping_cost: order.shipping_cost,
      total: order.total
    }
  end
end
