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

  alias ZeroCoupled.Lines

  alias ZeroCoupled.Domain.{
    CalculateSubtotal,
    ApplyDiscount,
    CalculateGiftWrapCost,
    CalculateShipping,
    ValidatePromo,
    ItemCount
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
            # pricing policy: configured instances the composition built once
            # (`shipping`, and optionally `promo`, `gift_wrap`). The aggregate
            # holds NO baked rates/codes and never looks inside them.
            pricing: %{},
            # derived — recomputed by recalc/1, never set directly:
            subtotal: Money.new(0),
            discount: Money.new(0),
            gift_wrap_total: Money.new(0),
            shipping_cost: Money.new(0),
            total: Money.new(0),
            item_count: 0

  @doc "Build a cart from persisted items and the composition's configured pricing instances."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      cart_id: Keyword.get(opts, :cart_id),
      items: Keyword.get(opts, :items, []),
      pricing: Keyword.get(opts, :pricing, %{})
    }
    |> recalc()
  end

  # ── Queries ──────────────────────────────────────────────────────────

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{items: items}), do: items == []

  @spec gift_wrapped?(t(), term()) :: boolean()
  def gift_wrapped?(%__MODULE__{gift_wrapped_ids: ids}, item_id),
    do: MapSet.member?(ids, item_id)

  @spec id(t()) :: term()
  def id(%__MODULE__{cart_id: id}), do: id

  @spec items(t()) :: [item()]
  def items(%__MODULE__{items: items}), do: items

  # ── Commands (return explicit facts for the wiring layer) ────────────

  @spec update_quantity(t(), term(), integer()) :: {:ok, t(), item()} | :error
  def update_quantity(%__MODULE__{} = cart, item_id, delta) do
    case Lines.bump(cart.items, item_id, delta) do
      {:ok, items, item} -> {:ok, recalc(%{cart | items: items}), item}
      :error -> :error
    end
  end

  @spec remove_item(t(), term()) :: {:ok, t(), item()} | :error
  def remove_item(%__MODULE__{} = cart, item_id) do
    case Lines.remove(cart.items, item_id) do
      {:ok, remaining, removed} ->
        cart =
          recalc(%{
            cart
            | items: remaining,
              gift_wrapped_ids: MapSet.delete(cart.gift_wrapped_ids, item_id)
          })

        {:ok, cart, removed}

      :error ->
        :error
    end
  end

  @doc "Add an item back (from undo, save-for-later, or wishlist). Idempotent by id."
  @spec add_item(t(), item()) :: {:ok, t(), item()}
  def add_item(%__MODULE__{} = cart, item),
    do: {:ok, recalc(%{cart | items: Lines.add(cart.items, item)}), item}

  @spec toggle_gift_wrap(t(), term()) :: {:ok, t(), item(), boolean()} | :error
  def toggle_gift_wrap(%__MODULE__{} = cart, item_id) do
    case Lines.find(cart.items, item_id) do
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

  @spec apply_promo(t(), String.t()) :: {:ok, t()} | {:error, :invalid_code}
  def apply_promo(%__MODULE__{} = cart, code) do
    case promo(cart.pricing, code) do
      {:ok, pct} ->
        {:ok,
         recalc(%{cart | promo_code: String.upcase(String.trim(code)), promo_percentage: pct})}

      {:error, :invalid_code} = err ->
        err
    end
  end

  @doc "Apply a new stock level to a product; returns the affected item if present."
  @spec set_stock(t(), term(), integer()) :: {:ok, t(), item()} | :none
  def set_stock(%__MODULE__{} = cart, product_id, new_stock) do
    case Lines.set_stock(cart.items, product_id, new_stock) do
      {:ok, items, item} -> {:ok, %{cart | items: items}, item}
      :none -> :none
    end
  end

  # The one place derived values are computed — pure composition of
  # single-function domain abstractions.
  defp recalc(%__MODULE__{} = cart) do
    subtotal = CalculateSubtotal.call(cart.items)
    {after_discount, discount} = ApplyDiscount.call(subtotal, cart.promo_percentage)

    gift_wrap = gift_wrap(cart.pricing, MapSet.size(cart.gift_wrapped_ids))
    shipping = shipping(cart.pricing, cart.shipping_method, subtotal)

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

  # a store may configure no promo codes or gift wrap
  defp promo(%{promo: promo}, code), do: ValidatePromo.call(promo, code)
  defp promo(_pricing, _code), do: {:error, :invalid_code}
  defp gift_wrap(%{gift_wrap: wrap}, count), do: CalculateGiftWrapCost.call(wrap, count)
  defp gift_wrap(_pricing, _count), do: 0

  defp shipping(%{shipping: shipping}, method, subtotal),
    do: CalculateShipping.call(shipping, method, subtotal)

  defp shipping(_pricing, _method, _subtotal), do: 0
end
