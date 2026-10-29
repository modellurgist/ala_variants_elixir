defmodule GoodDeal.State.CartLines do
  @moduledoc """
  What's in a shopper's cart or a buyer's order: its id, its stored lines (on `GoodDeal.Lines`) and
  which of them are gift-wrapped. One abstraction for both, since both are lines with quantities;
  what differs between them is priced elsewhere. It prices nothing; `contents` hands whatever totals them only what pricing reads:
  each line's quantity and product amount, and how many lines are wrapped. Ports out:

    * `:rows`      a change to the displayed lines: `{:reset | :added | :changed | :removed, row}`
    * `:contents`  `%{lines: [%{quantity, product: %{amount}}], wrapped_count}`, after any change
    * `:removed` / `:saved`  the line that left, and why
    * `:line`      a line handed out on request (to the wishlist, say)
    * `:changed`   what to write to the store: `{:quantity, cart_id, item_id, qty}`, or a removed
      line `{:aside, :held, cart_id, item_id}` until it is `{:kept, ...}` again or `{:removed, ...}` for
      good, a saved one `{:aside, :saved, cart_id, item_id}` until it is `{:kept, ...}`
    * `:checkout_requested`  the cart's id and stored lines, `{cart_id, items}`, never the cart
  """
  alias GoodDeal.Lines
  alias GoodDeal.Domain.StockStatus

  defstruct cart_id: nil, items: [], wrapped: MapSet.new(), stock_status: nil

  def ports,
    do: %{
      in: [
        load: :items,
        update_quantity: :event,
        remove: :event,
        save_for_later: :event,
        receive: :item,
        confirm_removal: :item_id,
        line: :event,
        toggle_gift_wrap: :event,
        set_stock: :stock_change,
        request_checkout: :event
      ],
      out: [
        rows: :row_change,
        contents: :contents,
        removed: :item,
        saved: :item,
        line: :line,
        changed: :cart_change,
        checkout_requested: :checkout_request
      ]
    }

  @doc "Config: `cart_id`, and `stock_status` (a configured `StockStatus`) for the rows."
  def new(opts), do: %__MODULE__{cart_id: opts[:cart_id], stock_status: opts[:stock_status]}

  @doc "The persisted lines arrive: the whole display resets to them."
  def load(%__MODULE__{} = cart, items) do
    cart = %{cart | items: items, wrapped: MapSet.new()}
    {cart, [rows: {:reset, Enum.map(items, &row(cart, &1))}, contents: contents(cart)]}
  end

  @doc "A quantity changes: by a step (`delta`), or to an absolute `quantity` (never below 1)."
  def update_quantity(%__MODULE__{} = cart, %{item_id: id, quantity: quantity}) do
    case Lines.find(cart.items, id) do
      %{quantity: current} ->
        update_quantity(cart, %{item_id: id, delta: max(quantity, 1) - current})

      nil ->
        {cart, []}
    end
  end

  def update_quantity(%__MODULE__{} = cart, %{item_id: id, delta: delta}) do
    case Lines.bump(cart.items, id, delta) do
      {:ok, items, item} ->
        cart = %{cart | items: items}

        {cart,
         [
           rows: {:changed, row(cart, item)},
           contents: contents(cart),
           changed: {:quantity, cart.cart_id, id, item.quantity}
         ]}

      :error ->
        {cart, []}
    end
  end

  def remove(%__MODULE__{} = cart, %{item_id: id}),
    do: set_aside(cart, id, :held, &[removed: &1])

  def save_for_later(%__MODULE__{} = cart, %{item_id: id}),
    do: set_aside(cart, id, :saved, &[saved: &1])

  @doc """
  A line comes (back) into the cart: an undone removal, a saved item, a wishlisted product. With a
  quantity, a persisted line joins at that quantity, and a line already there grows by it.
  """
  def receive(%__MODULE__{} = cart, {item, quantity}) do
    already = Lines.find(cart.items, item.id)
    items = Lines.add(cart.items, item)
    target = if already, do: already.quantity + quantity, else: max(quantity, 1)
    {:ok, items, line} = Lines.bump(items, item.id, target - Lines.find(items, item.id).quantity)
    cart = %{cart | items: items}

    {cart,
     [
       rows: {:added, row(cart, line)},
       contents: contents(cart),
       changed: {:quantity, cart.cart_id, line.id, line.quantity}
     ]}
  end

  def receive(%__MODULE__{} = cart, item) do
    cart = %{cart | items: Lines.add(cart.items, item)}

    {cart,
     [
       rows: {:added, row(cart, item)},
       contents: contents(cart),
       changed: {:kept, cart.cart_id, item.id}
     ]}
  end

  @doc "A removal is final: write it."
  def confirm_removal(%__MODULE__{} = cart, item_id),
    do: {cart, [changed: {:removed, cart.cart_id, item_id}]}

  def line(%__MODULE__{} = cart, %{item_id: id}), do: {cart, [line: Lines.find(cart.items, id)]}

  def toggle_gift_wrap(%__MODULE__{} = cart, %{item_id: id}) do
    case Lines.find(cart.items, id) do
      nil ->
        {cart, []}

      item ->
        cart = %{cart | wrapped: toggle(cart.wrapped, id)}
        {cart, [rows: {:changed, row(cart, item)}, contents: contents(cart)]}
    end
  end

  def set_stock(%__MODULE__{} = cart, %{product_id: product_id, stock: stock}) do
    case Lines.set_stock(cart.items, product_id, stock) do
      {:ok, items, item} ->
        cart = %{cart | items: items}
        {cart, [rows: {:changed, row(cart, item)}]}

      :none ->
        {cart, []}
    end
  end

  @doc "The shopper wants to pay: the cart's id and stored lines go out, not the cart itself."
  def request_checkout(%__MODULE__{} = cart, _),
    do: {cart, [checkout_requested: {cart.cart_id, cart.items}]}

  # the line leaves the displayed cart but stays stored, marked, until it comes back or goes for good
  defp set_aside(cart, id, mark, why) do
    case Lines.remove(cart.items, id) do
      {:ok, remaining, item} ->
        row = row(cart, item)
        cart = %{cart | items: remaining, wrapped: MapSet.delete(cart.wrapped, id)}

        {cart,
         [rows: {:removed, row}] ++
           why.(item) ++
           [contents: contents(cart), changed: {:aside, mark, cart.cart_id, id}]}

      :error ->
        {cart, []}
    end
  end

  defp toggle(set, id),
    do: if(MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id))

  defp contents(cart),
    do: %{
      lines:
        for(i <- cart.items, do: %{quantity: i.quantity, product: %{amount: i.product.amount}}),
      wrapped_count: MapSet.size(cart.wrapped)
    }

  # the projected value a displayed line carries: a neutral shape, never the item struct
  defp row(cart, item) do
    %{
      id: item.id,
      product_id: item.product.id,
      product: %{
        thumbnail: item.product.thumbnail,
        name: item.product.name,
        amount: item.product.amount
      },
      stock_status: StockStatus.call(cart.stock_status, item.product.stock),
      quantity: item.quantity,
      line_total: Money.new(item.product.amount * item.quantity),
      gift_wrapped: MapSet.member?(cart.wrapped, item.id)
    }
  end
end
