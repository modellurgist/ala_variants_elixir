defmodule ZeroCoupled.Features.OrderLines do
  @moduledoc """
  A bulk order's lines: the same `ZeroCoupled.Cart` aggregate the storefront uses, priced by
  volume tier instead of promo code, with absolute quantities. Ports out: `:rows`, `:summary`,
  `:removed`, `:persist`, as for the cart.
  """
  alias ZeroCoupled.Cart
  alias ZeroCoupled.Domain.{ShippingInfo, StockStatus, VolumeTier}

  def new(opts) do
    opts[:pricing]
    |> Map.new()
    |> then(&Cart.new(cart_id: opts[:cart_id], items: opts[:items] || [], config: &1))
    |> reprice()
  end

  def find(%Cart{items: items}, item_id), do: Enum.find(items, &(&1.id == item_id))

  def find_by_product(%Cart{items: items}, product_id),
    do: Enum.find(items, &(&1.product.id == product_id))

  def load(%Cart{} = order, items) do
    order = reprice(Cart.new(cart_id: order.cart_id, items: items, config: order.config))
    {order, [rows: {:reset, rows(order)}, summary: summary(order)]}
  end

  @doc "Set a line to an absolute quantity (never below 1)."
  def set_quantity(%Cart{} = order, %{item_id: item_id, quantity: quantity}) do
    with %{quantity: current} <- find(order, item_id),
         {:ok, order, line} <- Cart.update_quantity(order, item_id, max(quantity, 1) - current) do
      order = reprice(order)

      {order,
       [
         rows: {:changed, row(line)},
         summary: summary(order),
         persist: {:quantity, order.cart_id, item_id, line.quantity}
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
       rows: {:added, row(line)},
       summary: summary(order),
       persist: {:quantity, order.cart_id, line.id, line.quantity}
     ]}
  end

  def remove(%Cart{} = order, %{item_id: item_id}) do
    case Cart.remove_item(order, item_id) do
      {:ok, order, line} ->
        order = reprice(order)
        {order, [rows: {:removed, row(line)}, removed: line, summary: summary(order)]}

      :error ->
        {order, []}
    end
  end

  def receive(%Cart{} = order, item) do
    {:ok, order, line} = Cart.add_item(order, item)
    order = reprice(order)
    {order, [rows: {:added, row(line)}, summary: summary(order)]}
  end

  def confirm_removal(%Cart{} = order, item_id),
    do: {order, [persist: {:remove, order.cart_id, item_id}]}

  def set_stock(%Cart{} = order, %{product_id: product_id, stock: stock}) do
    case Cart.set_stock(order, product_id, stock) do
      {:ok, order, line} -> {order, [rows: {:changed, row(line)}]}
      :none -> {order, []}
    end
  end

  defp reprice(%Cart{} = order) do
    {pct, _label} = VolumeTier.call(order.subtotal.amount, tiers(order))
    Cart.set_discount(order, pct)
  end

  defp tiers(order), do: order.config[:volume_tiers] || []

  def row(line) do
    %{
      id: line.id,
      product: %{
        thumbnail: line.product.thumbnail,
        name: line.product.name,
        amount: line.product.amount
      },
      stock_status: StockStatus.call(line.product.stock),
      quantity: line.quantity,
      line_total: Money.new(line.product.amount * line.quantity)
    }
  end

  def rows(%Cart{items: items}), do: Enum.map(items, &row/1)

  def summary(%Cart{} = order) do
    {_pct, tier_label} = VolumeTier.call(order.subtotal.amount, tiers(order))
    rates = order.config[:shipping] || %{}

    %{
      empty?: Cart.empty?(order),
      item_count: order.item_count,
      subtotal: order.subtotal,
      discount: order.discount,
      tier_label: tier_label,
      shipping_label: ShippingInfo.label(order.shipping_method, rates),
      shipping_cost: order.shipping_cost,
      total: order.total
    }
  end
end
