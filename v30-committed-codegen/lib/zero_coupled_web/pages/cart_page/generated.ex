# ══════════════════════════════════════════════════════════════════════
# GENERATED FILE — do not edit.
# Source of truth: ZeroCoupledWeb.CartPage.Manifest (change it first, then run
# `mix zc.gen`). `mix zc.gen --check` fails the build on drift.
# ══════════════════════════════════════════════════════════════════════
defmodule ZeroCoupledWeb.CartPage.Session do
  @moduledoc "Generated session struct: one field per manifest slot."
  defstruct cart: nil, undo: nil, saved: nil, wishlist: nil, checkout: nil, ui: nil

  def new(opts \\ []) do
    struct!(__MODULE__,
      cart: ZeroCoupled.Features.CartItems.init(opts),
      undo: ZeroCoupled.Features.Undo.init(opts),
      saved: ZeroCoupled.Features.SavedItems.init(opts),
      wishlist: ZeroCoupled.Features.Wishlist.init(opts),
      checkout: ZeroCoupled.Features.CheckoutFlow.init(opts),
      ui: ZeroCoupled.Features.PageUI.init(opts)
    )
  end
end

defmodule ZeroCoupledWeb.CartPage.Generated do
  @moduledoc "Generated glue for the page. **Do not edit** — regenerate with\n`mix zc.gen` after changing the Manifest.\n"
  import Phoenix.Component, only: [assign: 3]
  alias ZeroCoupledWeb.CartPage.Session

  (
    @doc "Pure runner: an intent closure → its facts → `{session, effects}`."
    def run_pure(session, fun) when is_function(fun, 1) do
      case fun.(session) do
        {session, effects} -> apply_facts(session, effects, [])
        {session, effects, facts} -> apply_facts(session, effects, facts)
      end
    end
  )

  (
    @doc "Pure runner by intent name or `{module, function}`."
    def run_intent(session, name, args) when is_atom(name) do
      run_intent(session, intent_owner(name), args)
    end
  )

  def run_intent(session, {mod, fun}, args) do
    run_pure(session, fn session -> apply(mod, fun, [session, args]) end)
  end

  defp apply_facts(session, effects, facts) do
    Enum.reduce(facts, {session, effects}, fn fact, {session, effects} ->
      {session, more} = apply_fact(session, fact)
      {session, effects ++ more}
    end)
  end

  def intent_owner(:update_quantity) do
    {ZeroCoupled.Features.CartItems.Intents, :update_quantity}
  end

  def intent_owner(:remove_item) do
    {ZeroCoupled.Features.CartItems.Intents, :remove_item}
  end

  def intent_owner(:save_for_later) do
    {ZeroCoupled.Features.CartItems.Intents, :save_for_later}
  end

  def intent_owner(:toggle_gift_wrap) do
    {ZeroCoupled.Features.CartItems.Intents, :toggle_gift_wrap}
  end

  def intent_owner(:select_shipping) do
    {ZeroCoupled.Features.CartItems.Intents, :select_shipping}
  end

  def intent_owner(:apply_promo) do
    {ZeroCoupled.Features.CartItems.Intents, :apply_promo}
  end

  def intent_owner(:undo_remove) do
    {ZeroCoupled.Features.Undo.Intents, :undo_remove}
  end

  def intent_owner(:move_to_cart) do
    {ZeroCoupled.Features.SavedItems.Intents, :move_to_cart}
  end

  def intent_owner(:toggle_wishlist) do
    {ZeroCoupled.Features.Wishlist.Intents, :toggle_wishlist}
  end

  def intent_owner(:remove_wishlist) do
    {ZeroCoupled.Features.Wishlist.Intents, :remove_wishlist}
  end

  def intent_owner(:start_checkout) do
    {ZeroCoupled.Features.CheckoutFlow.Intents, :start_checkout}
  end

  def intent_owner(:edit_address) do
    {ZeroCoupled.Features.CheckoutFlow.Intents, :edit_address}
  end

  def intent_owner(:switch_tab) do
    {ZeroCoupled.Features.PageUI.Intents, :switch_tab}
  end

  def intent_owner(name) do
    raise ArgumentError,
          "unknown intent #{inspect(name)} — declare it with `intent` in a feature's Intents module"
  end

  def apply_fact(session, %ZeroCoupled.Features.CartItems.Facts.ItemRemoved{} = fact) do
    effects = []

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.Undo.Intents.capture_removed(Map.fetch!(session, :undo), payload)

      session = Map.replace!(session, :undo, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(session, %ZeroCoupled.Features.Undo.Facts.ItemRestored{} = fact) do
    effects = []

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.CartItems.Intents.receive_item(Map.fetch!(session, :cart), payload)

      session = Map.replace!(session, :cart, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(session, %ZeroCoupled.Features.SavedItems.Facts.MovedToCart{} = fact) do
    effects = []

    (
      payload = (&%{item: &1.saved_item}).(fact)

      {new_slot, more} =
        ZeroCoupled.Features.CartItems.Intents.receive_item(Map.fetch!(session, :cart), payload)

      session = Map.replace!(session, :cart, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(session, %ZeroCoupled.Features.CartItems.Facts.ItemSaved{} = fact) do
    effects = []

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.SavedItems.Intents.stash(Map.fetch!(session, :saved), payload)

      session = Map.replace!(session, :saved, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(session, %ZeroCoupled.Features.Undo.Facts.RemovalFinal{} = fact) do
    effects = []

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.CartItems.Intents.confirm_removal(
          Map.fetch!(session, :cart),
          payload
        )

      session = Map.replace!(session, :cart, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(session, %ZeroCoupled.Features.CartItems.Facts.PromoApplied{} = fact) do
    effects = []

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.PageUI.Intents.clear_promo_error(Map.fetch!(session, :ui), payload)

      session = Map.replace!(session, :ui, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(session, %ZeroCoupled.Features.CartItems.Facts.PromoRejected{} = fact) do
    effects = []

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.PageUI.Intents.set_promo_error(Map.fetch!(session, :ui), payload)

      session = Map.replace!(session, :ui, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(session, %ZeroCoupled.Features.CartItems.Facts.AddedFromWishlist{} = fact) do
    effects = []

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.Wishlist.Intents.drop_product(
          Map.fetch!(session, :wishlist),
          payload
        )

      session = Map.replace!(session, :wishlist, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(_session, fact) do
    raise ArgumentError,
          "undeclared fact #{inspect(fact)} — add a `react` entry to the page Manifest"
  end

  def page_event("update_quantity", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, item_id: :int, delta: :int)

    run.(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.update_quantity(session, args)
    end)
  end

  def page_event("remove_item", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, item_id: :int)

    run.(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.remove_item(session, args)
    end)
  end

  def page_event("save_for_later", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, item_id: :int)

    run.(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.save_for_later(session, args)
    end)
  end

  def page_event("toggle_gift_wrap", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, item_id: :int)

    run.(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.toggle_gift_wrap(session, args)
    end)
  end

  def page_event("select_shipping", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, method: :atom)

    run.(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.select_shipping(session, args)
    end)
  end

  def page_event("apply_promo", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, code: :string)

    run.(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.apply_promo(session, args)
    end)
  end

  def page_event("undo_remove", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, [])
    run.(socket, fn session -> ZeroCoupled.Features.Undo.Intents.undo_remove(session, args) end)
  end

  def page_event("move_to_cart", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, item_id: :int)

    run.(socket, fn session ->
      ZeroCoupled.Features.SavedItems.Intents.move_to_cart(session, args)
    end)
  end

  def page_event("toggle_wishlist", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, item_id: :int)

    run.(socket, fn session ->
      ZeroCoupled.Features.Wishlist.Intents.toggle_wishlist(session, args)
    end)
  end

  def page_event("remove_wishlist", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, product_id: :int)

    run.(socket, fn session ->
      ZeroCoupled.Features.Wishlist.Intents.remove_wishlist(session, args)
    end)
  end

  def page_event("start_checkout", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, [])

    run.(socket, fn session ->
      ZeroCoupled.Features.CheckoutFlow.Intents.start_checkout(session, args)
    end)
  end

  def page_event("edit_address", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, [])

    run.(socket, fn session ->
      ZeroCoupled.Features.CheckoutFlow.Intents.edit_address(session, args)
    end)
  end

  def page_event("switch_tab", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, tab: :atom)
    run.(socket, fn session -> ZeroCoupled.Features.PageUI.Intents.switch_tab(session, args) end)
  end

  def page_event(event, _params, _socket, _run) do
    raise ArgumentError,
          "unknown event #{inspect(event)} — declare an `intent` or add a hand-written handle_event clause"
  end

  def page_render(%{live_action: :checkout} = assigns) do
    ZeroCoupledWeb.CartLive.CheckoutView.render(assigns)
  end

  def page_render(assigns) do
    ZeroCoupledWeb.CartLive.IndexView.render(assigns)
  end

  (
    @doc "Initialize the session (and timers) into assigns at mount."
    def mount_session(socket, opts \\ []) do
      socket |> assign(:timers, %{}) |> put_session(Session.new(opts))
    end
  )

  (
    @doc "Assign a new session: per-slot assigns plus any gated render_data slots."
    def put_session(socket, session) do
      stale_cart = render_stale?(socket, :cart_slot, Map.fetch!(session, :cart))

      socket =
        socket
        |> assign(:session, session)
        |> assign(:cart_slot, Map.fetch!(session, :cart))
        |> assign(:undo_slot, Map.fetch!(session, :undo))
        |> assign(:saved_slot, Map.fetch!(session, :saved))
        |> assign(:wishlist_slot, Map.fetch!(session, :wishlist))
        |> assign(:checkout_slot, Map.fetch!(session, :checkout))
        |> assign(:ui_slot, Map.fetch!(session, :ui))

      socket =
        if stale_cart do
          assign(
            socket,
            :cart,
            ZeroCoupled.Features.CartItems.render_data(Map.fetch!(session, :cart))
          )
        else
          socket
        end

      socket
    end
  )

  defp render_stale?(socket, slot_key, value) do
    case socket.assigns do
      %{^slot_key => prev} -> not :erts_debug.same(prev, value)
      _ -> true
    end
  end

  (
    @doc false
    def __manifest__ do
      %{
        action_views: [
          index: ZeroCoupledWeb.CartLive.IndexView,
          checkout: ZeroCoupledWeb.CartLive.CheckoutView
        ],
        features: [
          {:cart, ZeroCoupled.Features.CartItems, render: :render_data},
          {:undo, ZeroCoupled.Features.Undo, []},
          {:saved, ZeroCoupled.Features.SavedItems, []},
          {:wishlist, ZeroCoupled.Features.Wishlist, []},
          {:checkout, ZeroCoupled.Features.CheckoutFlow, []},
          {:ui, ZeroCoupled.Features.PageUI, []}
        ],
        intents: [
          {:update_quantity, :cart, ZeroCoupled.Features.CartItems.Intents,
           item_id: :int, delta: :int},
          {:remove_item, :cart, ZeroCoupled.Features.CartItems.Intents, item_id: :int},
          {:save_for_later, :cart, ZeroCoupled.Features.CartItems.Intents, item_id: :int},
          {:toggle_gift_wrap, :cart, ZeroCoupled.Features.CartItems.Intents, item_id: :int},
          {:select_shipping, :cart, ZeroCoupled.Features.CartItems.Intents, method: :atom},
          {:apply_promo, :cart, ZeroCoupled.Features.CartItems.Intents, code: :string},
          {:undo_remove, :undo, ZeroCoupled.Features.Undo.Intents, []},
          {:move_to_cart, :saved, ZeroCoupled.Features.SavedItems.Intents, item_id: :int},
          {:toggle_wishlist, :wishlist, ZeroCoupled.Features.Wishlist.Intents, item_id: :int},
          {:remove_wishlist, :wishlist, ZeroCoupled.Features.Wishlist.Intents, product_id: :int},
          {:start_checkout, :checkout, ZeroCoupled.Features.CheckoutFlow.Intents, []},
          {:edit_address, :checkout, ZeroCoupled.Features.CheckoutFlow.Intents, []},
          {:switch_tab, :ui, ZeroCoupled.Features.PageUI.Intents, tab: :atom}
        ],
        reactions: [
          {ZeroCoupled.Features.CartItems.Facts.ItemRemoved,
           [{:undo, ZeroCoupled.Features.Undo.Intents, :capture_removed, transform: false}]},
          {ZeroCoupled.Features.Undo.Facts.ItemRestored,
           [{:cart, ZeroCoupled.Features.CartItems.Intents, :receive_item, transform: false}]},
          {ZeroCoupled.Features.SavedItems.Facts.MovedToCart,
           [{:cart, ZeroCoupled.Features.CartItems.Intents, :receive_item, transform: true}]},
          {ZeroCoupled.Features.CartItems.Facts.ItemSaved,
           [{:saved, ZeroCoupled.Features.SavedItems.Intents, :stash, transform: false}]},
          {ZeroCoupled.Features.Undo.Facts.RemovalFinal,
           [{:cart, ZeroCoupled.Features.CartItems.Intents, :confirm_removal, transform: false}]},
          {ZeroCoupled.Features.CartItems.Facts.PromoApplied,
           [{:ui, ZeroCoupled.Features.PageUI.Intents, :clear_promo_error, transform: false}]},
          {ZeroCoupled.Features.CartItems.Facts.PromoRejected,
           [{:ui, ZeroCoupled.Features.PageUI.Intents, :set_promo_error, transform: false}]},
          {ZeroCoupled.Features.CartItems.Facts.AddedFromWishlist,
           [{:wishlist, ZeroCoupled.Features.Wishlist.Intents, :drop_product, transform: false}]}
        ]
      }
    end
  )
end
