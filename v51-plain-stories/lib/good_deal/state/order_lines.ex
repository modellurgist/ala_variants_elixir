defmodule GoodDeal.State.OrderLines do
  @moduledoc """
  A bulk order's lines, priced by volume tier, with absolute quantities. Its data is its own: it
  builds on `GoodDeal.Lines`, the list of order lines both use cases share, not on the storefront's
  cart, which carries promo, gift-wrap and shipping-choice state the portal has no use for (Spray
  §6.17.2). Ports out: `:rows`, `:summary`, `:removed`, `:changed`, `:review`.
  """
  alias GoodDeal.Lines

  alias GoodDeal.Domain.{
    ApplyDiscount,
    CalculateShipping,
    CalculateSubtotal,
    ItemCount,
    StockStatus,
    VolumeTier
  }

  defstruct cart_id: nil,
            items: [],
            pricing: %{},
            shipping_method: :standard,
            # derived by recalc/1
            subtotal: Money.new(0),
            discount: Money.new(0),
            shipping_cost: Money.new(0),
            total: Money.new(0),
            item_count: 0,
            tier_label: nil

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

  @doc "Config: `cart_id`, `items`, and the pricing instances the composition built once (`shipping`, `volume`, `stock_status`)."
  def new(opts),
    do:
      recalc(%__MODULE__{
        cart_id: opts[:cart_id],
        items: opts[:items] || [],
        pricing: opts[:pricing]
      })

  defp find(%__MODULE__{items: items}, item_id), do: Lines.find(items, item_id)

  @doc "The buyer wants to review the order: its summary goes out."
  def request_review(%__MODULE__{} = order, _), do: {order, [review: summary(order)]}

  def load(%__MODULE__{} = order, items) do
    order = recalc(%{order | items: items})
    {order, [rows: {:reset, rows(order)}, summary: summary(order)]}
  end

  @doc "Set a line to an absolute quantity (never below 1)."
  def set_quantity(%__MODULE__{} = order, %{item_id: item_id, quantity: quantity}) do
    with %{quantity: current} <- find(order, item_id),
         {:ok, items, line} <- Lines.bump(order.items, item_id, max(quantity, 1) - current) do
      order = recalc(%{order | items: items})

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
  def add(%__MODULE__{} = order, {item, quantity}) do
    already = find(order, item.id)
    items = Lines.add(order.items, item)
    target = if already, do: already.quantity + quantity, else: max(quantity, 1)
    {:ok, items, line} = Lines.bump(items, item.id, target - Lines.find(items, item.id).quantity)
    order = recalc(%{order | items: items})

    {order,
     [
       rows: {:added, row(order, line)},
       summary: summary(order),
       changed: {:quantity, order.cart_id, line.id, line.quantity}
     ]}
  end

  def remove(%__MODULE__{} = order, %{item_id: item_id}) do
    case Lines.remove(order.items, item_id) do
      {:ok, remaining, line} ->
        order = recalc(%{order | items: remaining})
        {order, [rows: {:removed, row(order, line)}, removed: line, summary: summary(order)]}

      :error ->
        {order, []}
    end
  end

  def receive(%__MODULE__{} = order, item) do
    order = recalc(%{order | items: Lines.add(order.items, item)})
    {order, [rows: {:added, row(order, item)}, summary: summary(order)]}
  end

  def confirm_removal(%__MODULE__{} = order, item_id),
    do: {order, [changed: {:removed, order.cart_id, item_id}]}

  def set_stock(%__MODULE__{} = order, %{product_id: product_id, stock: stock}) do
    case Lines.set_stock(order.items, product_id, stock) do
      {:ok, items, line} -> {%{order | items: items}, [rows: {:changed, row(order, line)}]}
      :none -> {order, []}
    end
  end

  # the order's own pricing: subtotal, its volume tier's discount, then shipping on the subtotal
  defp recalc(%__MODULE__{items: items, pricing: pricing} = order) do
    subtotal = CalculateSubtotal.call(items)
    {pct, tier_label} = VolumeTier.call(pricing.volume, subtotal)
    {after_discount, discount} = ApplyDiscount.call(subtotal, pct)
    shipping = CalculateShipping.call(pricing.shipping, order.shipping_method, subtotal)

    %{
      order
      | subtotal: Money.new(subtotal),
        discount: Money.new(discount),
        shipping_cost: Money.new(shipping),
        total: Money.new(after_discount + shipping),
        item_count: ItemCount.call(items),
        tier_label: tier_label
    }
  end

  defp row(%__MODULE__{} = order, line) do
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

  defp rows(%__MODULE__{items: items} = order), do: Enum.map(items, &row(order, &1))

  defp summary(%__MODULE__{} = order) do
    %{
      empty?: order.items == [],
      item_count: order.item_count,
      subtotal: order.subtotal,
      discount: order.discount,
      tier_label: order.tier_label,
      shipping_label: CalculateShipping.label(order.pricing.shipping, order.shipping_method),
      shipping_cost: order.shipping_cost,
      total: order.total
    }
  end
end
