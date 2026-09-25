defmodule ZeroCoupled.Web.Contracts do
  @moduledoc """
  The single home for every cross-boundary **string contract** the presentation
  layer used to scatter: intent/event names, stream names, stream container
  dom-ids, and JS hook names. Markup references these functions (an interpolated
  event *port*); it never restates the literal. Change a name here, once.

  This is the §109 move applied to string contracts: both ends (server markup +
  the JS hook, or the effect emitter + the stream container) depend *downward*
  on this neutral module as knowledge, never *sideways* on each other's literal.
  `ContractPurity` fails the build when a literal is restated anywhere else;
  `mix zc.gen.contracts --check` keeps the generated JS half
  (`assets/js/contracts.js`) in sync.

  Not a presentation file (no markup), so the checkers do not scan it — the
  literals are *supposed* to live here, concentrated and greppable.
  """

  # ── Intent/event ports (phx-click / phx-change / phx-submit targets) ──────
  @events %{
    # storefront cart page
    add_wishlisted_to_cart: "add_wishlisted_to_cart",
    apply_promo: "apply_promo",
    edit_address: "edit_address",
    move_to_cart: "move_to_cart",
    pay: "pay",
    remove_item: "remove_item",
    remove_wishlist: "remove_wishlist",
    save_for_later: "save_for_later",
    select_shipping: "select_shipping",
    start_checkout: "start_checkout",
    submit_address: "submit_address",
    switch_tab: "switch_tab",
    toggle_gift_wrap: "toggle_gift_wrap",
    toggle_wishlist: "toggle_wishlist",
    undo_remove: "undo_remove",
    update_quantity: "update_quantity",
    validate_address: "validate_address",
    # B2B portal page (undo_remove is shared — same undo feature)
    add_to_order: "add_to_order",
    edit_lines: "edit_lines",
    go_review: "go_review",
    remove_line: "remove_line",
    set_line_quantity: "set_line_quantity",
    submit_order: "submit_order",
    validate_po: "validate_po"
  }

  @spec event(atom()) :: String.t()
  def event(name), do: Map.fetch!(@events, name)

  # ── Streams: slot → stream name → container dom-id (one relationship) ─────
  @streams %{
    cart: :cart_items,
    saved: :saved_items,
    wishlist: :wishlist_products,
    order: :order_lines,
    catalog: :portal_products
  }

  @spec stream_name(atom()) :: atom()
  def stream_name(slot), do: Map.fetch!(@streams, slot)

  @spec stream_dom_id(atom()) :: String.t()
  def stream_dom_id(slot), do: Atom.to_string(stream_name(slot))

  # ── JS hooks + the server↔JS push events they listen for ─────────────────
  @hooks %{auto_focus: "AutoFocus", remove_fade: "RemoveFade"}
  @push_events %{item_removed: "item-removed"}

  @spec hook(atom()) :: String.t()
  def hook(name), do: Map.fetch!(@hooks, name)

  @doc "Server side of a server→JS push contract (JS half generated from the same map)."
  @spec push_event(atom()) :: String.t()
  def push_event(name), do: Map.fetch!(@push_events, name)

  @doc """
  Reflection surface — the whole contract table in one place. Consumed by
  `mix zc.gen.contracts` to emit `assets/js/contracts.js` and to report any
  key referenced by nobody (a dead contract).
  """
  @spec __contracts__() :: %{atom() => %{atom() => String.t() | atom()}}
  def __contracts__ do
    %{events: @events, streams: @streams, hooks: @hooks, push_events: @push_events}
  end
end
