defmodule ZeroCoupledWeb.CartPage.Manifest do
  @moduledoc """
  The cart page's **diagram** — a plain data module (no macros, no
  `use`). Reading it answers: which capabilities exist on this page, who
  reacts to what, and what renders where.

  **Change this file first**, then run `mix zc.gen`. The committed glue
  in `generated.ex` is derived from it, and `mix zc.gen --check` fails
  the build if the two ever drift. Because it is ordinary Elixir, a
  typo'd fact alias or feature module is still a plain **compile error** —
  the V29.1 guarantee, kept without a macro.

  Intents are *not* listed here; they stay declared next to their
  functions in each feature's `Intents` module (`intent :remove_item,
  params: [...]`). The generator collects them and enforces single
  ownership.
  """

  alias ZeroCoupled.Features.{CartItems, Undo, SavedItems, Wishlist, CheckoutFlow, PageUI}
  alias ZeroCoupled.Features.CartItems.Facts, as: CartFacts
  alias ZeroCoupled.Features.Undo.Facts, as: UndoFacts
  alias ZeroCoupled.Features.SavedItems.Facts, as: SavedFacts
  alias ZeroCoupled.Foundation.Broadcast.Facts, as: BroadcastFacts
  alias ZeroCoupledWeb.CartLive.{IndexView, CheckoutView}

  # ── Calibration on the diagram (V34) ──────────────────────────────────
  # Every literal that makes this the *retail storefront* — shipping rates,
  # promo codes, gift-wrap price, the undo window — lives here, in one
  # readable place, and is injected into the (now generic) domain
  # abstractions via each slot's `config:`. Change the store's pricing by
  # editing this block; no domain module changes.
  @retail_pricing [
    shipping: %{
      standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
      express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
      overnight: %{label: "Overnight", cost: 2499, free_above: nil}
    },
    promo: %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50},
    gift_wrap_unit: 299
  ]

  @doc """
  Slot → feature. `render:` names the L5 presentation port; `config:` (V34)
  supplies the slot's calibration, spliced into `init/1` by the generator.
  ActionViews reference no feature or domain module (`ComponentPurity`-enforced).
  """
  def features do
    [
      cart: {CartItems, render: :render_data, config: [pricing: @retail_pricing]},
      undo: {Undo, render: :render_data, config: [window_ms: 5_000]},
      saved: {SavedItems, render: :render_data},
      wishlist: {Wishlist, render: :render_data},
      checkout: CheckoutFlow,
      ui: PageUI
    ]
  end

  @doc """
  Typed fact → slot-scoped reaction (single level). A reaction receives
  `Map.from_struct(fact)` unless a `transform:` translates the emitter's
  vocabulary into the reactor's port shape — see the MovedToCart wire.
  """
  def reactions do
    [
      {CartFacts.ItemRemoved, to: {:undo, Undo.Intents, :capture_removed}},
      {UndoFacts.ItemRestored, to: {:cart, CartItems.Intents, :receive_item}},
      {SavedFacts.MovedToCart,
       to: {:cart, CartItems.Intents, :receive_item, transform: &%{item: &1.saved_item}}},
      {CartFacts.ItemSaved, to: {:saved, SavedItems.Intents, :stash}},
      {UndoFacts.RemovalFinal, to: {:cart, CartItems.Intents, :confirm_removal}},
      {CartFacts.PromoApplied, to: {:ui, PageUI.Intents, :clear_promo_error}},
      {CartFacts.PromoRejected, to: {:ui, PageUI.Intents, :set_promo_error}},
      {CartFacts.AddedFromWishlist, to: {:wishlist, Wishlist.Intents, :drop_product}},
      # Cross-process fact (PubSub), routed like any in-process fact — the
      # page's generic handle_info forwards declared fact structs here
      # (V32 Enhancement B; formerly an untyped {:stock_changed, …} tuple).
      {BroadcastFacts.StockChanged, to: {:cart, CartItems.Intents, :set_stock}}
    ]
  end

  @doc "live_action → ActionView. `:index` is the render fallback."
  def action_views, do: [index: IndexView, checkout: CheckoutView]

  @doc """
  UI-event flows (V33): the checkout wizard's skeleton — which steps
  exist, which event advances which, where the milestones sit, and which
  steps have URLs — read off this table instead of living imperatively in
  the view and intents. The **result-fact** edges (async payment settled →
  `:complete`/`:error`) are deliberately absent: they belong to intents/
  `reactions/0` — each channel carries the edge type it is shaped for.

  Generated into two artifacts: `ZeroCoupled.Flows` (core; features
  consult their own flow's transitions) and this page's web glue
  (milestones, step URLs, param translation).
  """
  def flows do
    [
      checkout: [
        initial: :address,
        milestones: [address: "Address", payment: "Payment"],
        transitions: [
          {:address, :submit_address, :payment},
          {:payment, :edit_address, :address},
          {:payment, :pay, :processing},
          {:error, :pay, :processing}
        ],
        paths: [address: "/cart/checkout", payment: "/cart/checkout/payment"]
      ]
    ]
  end
end
