defmodule ZeroCoupled.Cart do
  @moduledoc """
  The cart **aggregate** — the single source of truth for cart contents,
  pricing, promo, gift-wrap flags, and shipping method.

  This is v28's answer to v27's biggest smell: v27 split one cohesive
  aggregate into `CartCore` plus satellite "features" (`GiftWrap`,
  `ShippingSelection`) that *duplicated* CartCore's state
  (`gift_wrapped_ids` lived in two places). Here there is exactly one
  place that knows about gift wrapping or shipping — no duplication,
  nothing to drift.

  It is a **pure, framework-free abstraction**. It composes the
  single-function domain abstractions (`CalculateSubtotal`,
  `ApplyDiscount`, …) and knows nothing about Phoenix, Ecto, or any of
  the independent capabilities (`Undo`, `SavedItems`, `Wishlist`,
  `Checkout`). Those are wired to it by `ZeroCoupled.Session`.

  Every mutating function returns an explicit, pattern-matchable result
  (`{:ok, cart, fact}` / `{:error, reason}`) so the wiring layer can
  react without the cart ever knowing a peer exists.
  """

  alias ZeroCoupled.Domain.{
    CalculateSubtotal,
    ApplyDiscount,
    CalculateGiftWrapCost,
    CalculateShipping,
    ItemCount,
    ValidatePromo,
    BuildLineItems,
    ValidateCheckout,
    CheckStock
  }

  @type item :: %{
          :id => term(),
          :quantity => non_neg_integer(),
          :product => %{:id => term(), :amount => integer(), optional(atom()) => any()},
          optional(atom()) => any()
        }

  @type t :: %__MODULE__{}

  defstruct cart_id: nil,
            items: [],
            gift_wrapped_ids: MapSet.new(),
            promo_code: nil,
            promo_percentage: nil,
            shipping_method: :standard,
            # pricing policy, injected by the composition (V34: the manifest
            # `config:` channel). The aggregate holds NO baked rates/codes.
            config: %{},
            # derived — recomputed by recalc/1, never set directly:
            subtotal: Money.new(0),
            discount: Money.new(0),
            gift_wrap_total: Money.new(0),
            shipping_cost: Money.new(0),
            total: Money.new(0),
            item_count: 0

  @doc "Build a cart from persisted items and the composition's pricing config."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      cart_id: Keyword.get(opts, :cart_id),
      items: Keyword.get(opts, :items, []),
      config: Keyword.get(opts, :config, %{})
    }
    |> recalc()
  end

  # ── Queries ──────────────────────────────────────────────────────────

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{items: items}), do: items == []

  @spec gift_wrapped?(t(), term()) :: boolean()
  def gift_wrapped?(%__MODULE__{gift_wrapped_ids: ids}, item_id),
    do: MapSet.member?(ids, item_id)

  @doc "Payment line items for the current cart (composes a domain abstraction)."
  @spec line_items(t()) :: [map()]
  def line_items(%__MODULE__{items: items}), do: BuildLineItems.call(items)

  @doc """
  Validate the cart is checkout-ready against fresh stock levels.
  Returns `:ok` or an error fact the wiring layer can surface.
  """
  @spec check_ready(t(), %{term() => integer()}) ::
          :ok | {:error, :empty_cart | :out_of_stock}
  def check_ready(%__MODULE__{items: items}, stock_levels) do
    with {:ok, items} <- ValidateCheckout.call(items) do
      CheckStock.call(items, stock_levels)
    end
  end

  # ── Commands (return explicit facts for the wiring layer) ────────────

  @spec update_quantity(t(), term(), integer()) :: {:ok, t(), item()} | :error
  def update_quantity(%__MODULE__{} = cart, item_id, delta) do
    case find(cart, item_id) do
      nil ->
        :error

      _item ->
        cart = recalc(%{cart | items: bump_quantity(cart.items, item_id, delta)})
        {:ok, cart, find(cart, item_id)}
    end
  end

  defp bump_quantity(items, item_id, delta) do
    Enum.map(items, fn
      %{id: ^item_id} = item -> %{item | quantity: max(1, item.quantity + delta)}
      item -> item
    end)
  end

  @spec remove_item(t(), term()) :: {:ok, t(), item()} | :error
  def remove_item(%__MODULE__{} = cart, item_id) do
    case pop(cart.items, item_id) do
      {nil, _} ->
        :error

      {removed, remaining} ->
        cart =
          recalc(%{
            cart
            | items: remaining,
              gift_wrapped_ids: MapSet.delete(cart.gift_wrapped_ids, item_id)
          })

        {:ok, cart, removed}
    end
  end

  @doc "Add an item back (from undo, save-for-later, or wishlist). Idempotent by id."
  @spec add_item(t(), item()) :: {:ok, t(), item()}
  def add_item(%__MODULE__{} = cart, item) do
    items =
      if Enum.any?(cart.items, &(&1.id == item.id)),
        do: cart.items,
        else: cart.items ++ [item]

    {:ok, recalc(%{cart | items: items}), item}
  end

  @spec toggle_gift_wrap(t(), term()) :: {:ok, t(), item(), boolean()} | :error
  def toggle_gift_wrap(%__MODULE__{} = cart, item_id) do
    case find(cart, item_id) do
      nil ->
        :error

      item ->
        {ids, wrapped?} =
          if MapSet.member?(cart.gift_wrapped_ids, item_id),
            do: {MapSet.delete(cart.gift_wrapped_ids, item_id), false},
            else: {MapSet.put(cart.gift_wrapped_ids, item_id), true}

        {:ok, recalc(%{cart | gift_wrapped_ids: ids}), item, wrapped?}
    end
  end

  @spec select_shipping(t(), atom()) :: t()
  def select_shipping(%__MODULE__{} = cart, method) when is_atom(method),
    do: recalc(%{cart | shipping_method: method})

  @doc """
  Apply an externally-computed discount percentage (e.g. a volume tier).
  Generalization added for the portal consumer (D6): `apply_promo/2` was
  the only discount entry point, and it is code-validated — promo-shaped.
  """
  @spec set_discount(t(), non_neg_integer() | nil) :: t()
  def set_discount(%__MODULE__{} = cart, percentage),
    do: recalc(%{cart | promo_percentage: percentage})

  @spec apply_promo(t(), String.t()) :: {:ok, t()} | {:error, :invalid_code}
  def apply_promo(%__MODULE__{} = cart, code) do
    case ValidatePromo.call(code, cart.config[:promo] || %{}) do
      {:ok, pct} ->
        {:ok, recalc(%{cart | promo_code: String.upcase(String.trim(code)), promo_percentage: pct})}

      {:error, :invalid_code} = err ->
        err
    end
  end

  @doc "Apply a new stock level to a product; returns the affected item if present."
  @spec set_stock(t(), term(), integer()) :: {:ok, t(), item()} | :none
  def set_stock(%__MODULE__{} = cart, product_id, new_stock) do
    items =
      Enum.map(cart.items, fn item ->
        if item.product.id == product_id,
          do: %{item | product: %{item.product | stock: new_stock}},
          else: item
      end)

    case Enum.find(items, &(&1.product.id == product_id)) do
      nil -> :none
      item -> {:ok, %{cart | items: items}, item}
    end
  end

  # ── Internals ────────────────────────────────────────────────────────

  defp find(%__MODULE__{items: items}, item_id), do: Enum.find(items, &(&1.id == item_id))

  defp pop(items, item_id) do
    case Enum.split_with(items, &(&1.id == item_id)) do
      {[removed | _], remaining} -> {removed, remaining}
      {[], remaining} -> {nil, remaining}
    end
  end

  # The one place derived values are computed — pure composition of
  # single-function domain abstractions.
  defp recalc(%__MODULE__{} = cart) do
    subtotal = CalculateSubtotal.call(cart.items)
    {after_discount, discount} = ApplyDiscount.call(subtotal, cart.promo_percentage)
    gift_wrap = CalculateGiftWrapCost.call(MapSet.size(cart.gift_wrapped_ids), cart.config[:gift_wrap_unit] || 0)
    shipping = CalculateShipping.call(cart.shipping_method, subtotal, cart.config[:shipping] || %{})

    %{
      cart
      | subtotal: Money.new(subtotal),
        discount: Money.new(discount),
        gift_wrap_total: Money.new(gift_wrap),
        shipping_cost: Money.new(shipping),
        total: Money.new(after_discount + gift_wrap + shipping),
        item_count: ItemCount.call(cart.items)
    }
  end
end
