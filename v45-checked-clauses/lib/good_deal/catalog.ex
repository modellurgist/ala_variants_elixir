defmodule GoodDeal.Catalog do
  @moduledoc """
  The store's calibration — the numbers that make this *this* shop, gathered in
  one place at the composition so the domain abstractions stay generic and
  reusable. Pages read it and pass its values down; no domain or feature module
  reaches up to it.
  """

  @doc "Shipping tiers by method. `free_above: nil` means never free."
  def rates do
    %{
      standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
      express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
      overnight: %{label: "Overnight", cost: 2499, free_above: nil}
    }
  end

  @doc "Gift-wrap fee per wrapped item, in cents."
  def gift_wrap_cents, do: 299

  @doc "Promo codes this store honours, mapping code to percent off."
  def promo_codes, do: %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}

  @doc "Portal volume pricing, highest tier first: `{minimum_subtotal_cents, percent, label}`."
  def volume_tiers, do: [{200_000, 10, "10% volume discount"}, {50_000, 5, "5% volume discount"}]

  @doc "At or below this stock count, an item counts as low stock."
  def low_stock_threshold, do: 5

  @doc "The currency every price and charge is in."
  def currency, do: "usd"

  @doc "How long a removal can be undone."
  def undo_window_ms, do: 5_000

  @doc "Words both pages show."
  def summary_texts,
    do: %{
      items: "Items",
      subtotal: "Subtotal",
      shipping: "Shipping",
      free: "Free",
      total: "Total"
    }

  def stock_texts, do: %{low_stock: "Low stock", out_of_stock: "Out of stock"}
  def remove_text, do: "Remove"
end
