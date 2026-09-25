defmodule Session do
  @moduledoc "Generated session struct: one field per feature slot."
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

(
  @doc "Initialize the session (and timers) into assigns at mount."
  def mount_session(socket, opts \\ []) do
    socket = Phoenix.Component.assign(socket, :timers, %{})
    put_session(socket, Session.new(opts))
  end

  @doc "The current session."
  def session(socket) do
    socket.assigns.session
  end

  @doc "Assign a new session (per-slot assigns + any render_data slots)."
  def put_session(socket, session) do
    socket = Phoenix.Component.assign(socket, :session, session)
    socket = Phoenix.Component.assign(socket, :cart_slot, Map.fetch!(session, :cart))
    socket = Phoenix.Component.assign(socket, :undo_slot, Map.fetch!(session, :undo))
    socket = Phoenix.Component.assign(socket, :saved_slot, Map.fetch!(session, :saved))
    socket = Phoenix.Component.assign(socket, :wishlist_slot, Map.fetch!(session, :wishlist))
    socket = Phoenix.Component.assign(socket, :checkout_slot, Map.fetch!(session, :checkout))
    socket = Phoenix.Component.assign(socket, :ui_slot, Map.fetch!(session, :ui))

    socket =
      Phoenix.Component.assign(
        socket,
        :cart,
        ZeroCoupled.Features.CartItems.render_data(Map.fetch!(session, :cart))
      )

    socket
  end

  @doc "Interpret effects against the socket."
  def apply_effects(socket, effects) do
    ZeroCoupledWeb.EffectInterpreter.apply_all(socket, effects, __effect_opts__())
  end
)

(
  @doc "Pure runner: call an intent closure, then apply its facts through\nthe manifest's reactions. Returns `{session, effects}` — the unit\nthe composed-page tests assert on.\n"
  def run_pure(session, fun) when is_function(fun, 1) do
    case fun.(session) do
      {session, effects} -> __apply_facts__(session, effects, [])
      {session, effects, facts} -> __apply_facts__(session, effects, facts)
    end
  end

  @doc "Pure runner by intent name (uses declared metadata) or `{module, function}`."
  def run_intent(session, name, args) when is_atom(name) do
    run_intent(session, __intent_owner__(name), args)
  end

  def run_intent(session, {mod, fun}, args) do
    run_pure(session, fn session -> apply(mod, fun, [session, args]) end)
  end

  defp __apply_facts__(session, effects, facts) do
    Enum.reduce(facts, {session, effects}, fn fact, {session, effects} ->
      {session, more} = __apply_fact__(session, fact)
      {session, effects ++ more}
    end)
  end

  defp run(socket, fun) do
    {session, effects} = run_pure(session(socket), fun)
    {:noreply, socket |> put_session(session) |> apply_effects(effects)}
  end
)

(
  defp __intent_owner__(:update_quantity) do
    {ZeroCoupled.Features.CartItems.Intents, :update_quantity}
  end

  defp __intent_owner__(:remove_item) do
    {ZeroCoupled.Features.CartItems.Intents, :remove_item}
  end

  defp __intent_owner__(:save_for_later) do
    {ZeroCoupled.Features.CartItems.Intents, :save_for_later}
  end

  defp __intent_owner__(:toggle_gift_wrap) do
    {ZeroCoupled.Features.CartItems.Intents, :toggle_gift_wrap}
  end

  defp __intent_owner__(:select_shipping) do
    {ZeroCoupled.Features.CartItems.Intents, :select_shipping}
  end

  defp __intent_owner__(:apply_promo) do
    {ZeroCoupled.Features.CartItems.Intents, :apply_promo}
  end

  defp __intent_owner__(:undo_remove) do
    {ZeroCoupled.Features.Undo.Intents, :undo_remove}
  end

  defp __intent_owner__(:move_to_cart) do
    {ZeroCoupled.Features.SavedItems.Intents, :move_to_cart}
  end

  defp __intent_owner__(:toggle_wishlist) do
    {ZeroCoupled.Features.Wishlist.Intents, :toggle_wishlist}
  end

  defp __intent_owner__(:remove_wishlist) do
    {ZeroCoupled.Features.Wishlist.Intents, :remove_wishlist}
  end

  defp __intent_owner__(:start_checkout) do
    {ZeroCoupled.Features.CheckoutFlow.Intents, :start_checkout}
  end

  defp __intent_owner__(:edit_address) do
    {ZeroCoupled.Features.CheckoutFlow.Intents, :edit_address}
  end

  defp __intent_owner__(:switch_tab) do
    {ZeroCoupled.Features.PageUI.Intents, :switch_tab}
  end

  defp __intent_owner__(name) do
    raise ArgumentError,
          "unknown intent #{inspect(name)} — declare it with `intent` in a feature's Intents module"
  end
)

(
  def __apply_fact__(session, %ZeroCoupled.Features.CartItems.Facts.ItemRemoved{} = fact) do
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

  def __apply_fact__(session, %ZeroCoupled.Features.Undo.Facts.ItemRestored{} = fact) do
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

  def __apply_fact__(session, %ZeroCoupled.Features.SavedItems.Facts.MovedToCart{} = fact) do
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

  def __apply_fact__(session, %ZeroCoupled.Features.CartItems.Facts.ItemSaved{} = fact) do
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

  def __apply_fact__(session, %ZeroCoupled.Features.Undo.Facts.RemovalFinal{} = fact) do
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

  def __apply_fact__(session, %ZeroCoupled.Features.CartItems.Facts.PromoApplied{} = fact) do
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

  def __apply_fact__(session, %ZeroCoupled.Features.CartItems.Facts.PromoRejected{} = fact) do
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

  def __apply_fact__(session, %ZeroCoupled.Features.CartItems.Facts.AddedFromWishlist{} = fact) do
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

  def __apply_fact__(_session, fact) do
    raise ArgumentError,
          "undeclared fact #{inspect(fact)} — add a `react` line to #{inspect(__MODULE__)}"
  end
)

(
  def page_event("update_quantity", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, item_id: :int, delta: :int)

    run(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.update_quantity(session, args)
    end)
  end

  def page_event("remove_item", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, item_id: :int)

    run(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.remove_item(session, args)
    end)
  end

  def page_event("save_for_later", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, item_id: :int)

    run(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.save_for_later(session, args)
    end)
  end

  def page_event("toggle_gift_wrap", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, item_id: :int)

    run(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.toggle_gift_wrap(session, args)
    end)
  end

  def page_event("select_shipping", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, method: :atom)

    run(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.select_shipping(session, args)
    end)
  end

  def page_event("apply_promo", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, code: :string)

    run(socket, fn session ->
      ZeroCoupled.Features.CartItems.Intents.apply_promo(session, args)
    end)
  end

  def page_event("undo_remove", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, [])
    run(socket, fn session -> ZeroCoupled.Features.Undo.Intents.undo_remove(session, args) end)
  end

  def page_event("move_to_cart", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, item_id: :int)

    run(socket, fn session ->
      ZeroCoupled.Features.SavedItems.Intents.move_to_cart(session, args)
    end)
  end

  def page_event("toggle_wishlist", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, item_id: :int)

    run(socket, fn session ->
      ZeroCoupled.Features.Wishlist.Intents.toggle_wishlist(session, args)
    end)
  end

  def page_event("remove_wishlist", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, product_id: :int)

    run(socket, fn session ->
      ZeroCoupled.Features.Wishlist.Intents.remove_wishlist(session, args)
    end)
  end

  def page_event("start_checkout", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, [])

    run(socket, fn session ->
      ZeroCoupled.Features.CheckoutFlow.Intents.start_checkout(session, args)
    end)
  end

  def page_event("edit_address", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, [])

    run(socket, fn session ->
      ZeroCoupled.Features.CheckoutFlow.Intents.edit_address(session, args)
    end)
  end

  def page_event("switch_tab", params, socket) do
    args = ZeroCoupledWeb.Page.cast_params(params, tab: :atom)
    run(socket, fn session -> ZeroCoupled.Features.PageUI.Intents.switch_tab(session, args) end)
  end

  def page_event(event, _params, socket) do
    raise ArgumentError,
          "unknown event #{inspect(event)} for #{inspect(__MODULE__)} — " <>
            "declare an `intent` or add a hand-written handle_event clause"
  end
)

(
  def page_render(%{live_action: :checkout} = assigns) do
    ZeroCoupledWeb.CartLive.CheckoutView.render(assigns)
  end

  def page_render(assigns) do
    ZeroCoupledWeb.CartLive.IndexView.render(assigns)
  end
)

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
        {:update_quantity, :cart, ZeroCoupled.Features.CartItems.Intents, item_id: :int,
         delta: :int},
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

(
  @impl true
  def render(assigns) do
    page_render(assigns)
  end
)
