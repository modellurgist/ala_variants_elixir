defmodule Shop.Cart do
  @moduledoc """
  The cart feature — a plain module with its own private struct and pure
  functions. It knows nothing of any peer feature (undo, wishlist, …); it
  composes only the generic `Pricing` domain calcs, with calibration passed in
  from the composition. Cross-feature consequences are returned as data (a
  removed item, outcomes) for the composition to wire — never called here.
  """
  alias Shop.{Outcome, Pricing}

  defstruct items: [], gift_wrapped: MapSet.new(), promo_pct: nil, promo_code: nil,
            shipping: :standard, pricing: %{}

  def new(opts) do
    %__MODULE__{items: opts[:items] || [], pricing: opts[:pricing] || %{}}
  end

  def find(%__MODULE__{items: items}, id), do: Enum.find(items, &(&1.id == id))

  def empty?(%__MODULE__{items: items}), do: items == []

  @doc "Totals as a plain map (the value a view reads — no peer knowledge)."
  def totals(%__MODULE__{} = c) do
    lines = Enum.map(c.items, &%{unit_amount: &1.product.amount, quantity: &1.quantity})
    sub = Pricing.subtotal(lines)
    {after_disc, disc} = Pricing.discount(sub, c.promo_pct)
    gift = Pricing.gift_wrap(MapSet.size(c.gift_wrapped), c.pricing[:gift_wrap] || 0)
    ship = Pricing.shipping(c.shipping, sub, c.pricing[:shipping] || %{})
    %{subtotal: sub, discount: disc, gift_wrap: gift, shipping: ship,
      total: after_disc + gift + ship, item_count: Enum.sum(Enum.map(c.items, & &1.quantity)),
      promo_code: c.promo_code, empty?: empty?(c)}
  end

  # (state, args) -> {state, outcomes} — or {state, extracted_value, outcomes}
  def update_quantity(%__MODULE__{} = c, id, delta) do
    case find(c, id) do
      nil -> {c, []}
      item ->
        item = %{item | quantity: max(1, item.quantity + delta)}
        c = %{c | items: replace(c.items, item)}
        {c, [Outcome.stream_insert(:cart, item)]}
    end
  end

  def remove_item(%__MODULE__{} = c, id) do
    case find(c, id) do
      nil -> {c, nil, []}
      item ->
        c = %{c | items: Enum.reject(c.items, &(&1.id == id)),
                  gift_wrapped: MapSet.delete(c.gift_wrapped, id)}
        {c, item, [Outcome.stream_delete(:cart, item)]}
    end
  end

  def add_item(%__MODULE__{} = c, item) do
    items = if find(c, item.id), do: c.items, else: c.items ++ [item]
    {%{c | items: items}, [Outcome.stream_insert(:cart, item)]}
  end

  def toggle_gift_wrap(%__MODULE__{} = c, id) do
    if find(c, id) do
      wrapped = if MapSet.member?(c.gift_wrapped, id),
        do: MapSet.delete(c.gift_wrapped, id), else: MapSet.put(c.gift_wrapped, id)
      {%{c | gift_wrapped: wrapped}, [Outcome.stream_insert(:cart, find(c, id))]}
    else
      {c, []}
    end
  end

  def select_shipping(%__MODULE__{} = c, method), do: {%{c | shipping: method}, []}

  def apply_promo(%__MODULE__{} = c, code) do
    case Pricing.promo(code, c.pricing[:promo] || %{}) do
      {:ok, pct} ->
        {%{c | promo_pct: pct, promo_code: String.upcase(String.trim(code))},
         [Outcome.flash(:info, "Promo applied")], :ok}
      :error ->
        {c, [Outcome.flash(:error, "Invalid promo code")], :error}
    end
  end

  defp replace(items, item), do: Enum.map(items, &if(&1.id == item.id, do: item, else: &1))
end
