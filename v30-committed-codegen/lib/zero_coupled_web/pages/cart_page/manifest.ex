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
  alias ZeroCoupledWeb.CartLive.{IndexView, CheckoutView}

  @doc "Slot → feature. `render:` names the L5 presentation port used at assign time."
  def features do
    [
      cart: {CartItems, render: :render_data},
      undo: Undo,
      saved: SavedItems,
      wishlist: Wishlist,
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
      {CartFacts.AddedFromWishlist, to: {:wishlist, Wishlist.Intents, :drop_product}}
    ]
  end

  @doc "live_action → ActionView. `:index` is the render fallback."
  def action_views, do: [index: IndexView, checkout: CheckoutView]
end
