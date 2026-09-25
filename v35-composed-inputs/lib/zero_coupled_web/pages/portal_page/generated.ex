# ══════════════════════════════════════════════════════════════════════
# GENERATED FILE — do not edit.
# Source of truth: ZeroCoupledWeb.PortalPage.Manifest (change it first, then run
# `mix zc.gen`). `mix zc.gen --check` fails the build on drift.
# ══════════════════════════════════════════════════════════════════════
defmodule ZeroCoupledWeb.PortalPage.Session do
  @moduledoc "Generated session struct: one field per manifest slot."
  defstruct order: nil, catalog: nil, undo: nil, flow: nil

  def new(opts \\ []) do
    struct!(__MODULE__,
      order:
        ZeroCoupled.Features.OrderLines.init(
          Keyword.put(opts, :config,
            pricing: [
              shipping: %{
                express: %{cost: 1299, free_above: nil, label: "Express (2–3 days)"},
                overnight: %{cost: 2499, free_above: nil, label: "Overnight"},
                standard: %{cost: 599, free_above: 5000, label: "Standard (5–7 days)"}
              },
              volume_tiers: [
                {200_000, 10, "10% volume discount"},
                {50000, 5, "5% volume discount"}
              ]
            ]
          )
        ),
      catalog: ZeroCoupled.Features.PortalCatalog.init(opts),
      undo: ZeroCoupled.Features.Undo.init(Keyword.put(opts, :config, window_ms: 5000)),
      flow: ZeroCoupled.Features.PortalSubmit.init(opts)
    )
  end
end

defmodule ZeroCoupledWeb.PortalPage.Generated do
  @moduledoc "Generated glue for the page. **Do not edit** — regenerate with\n`mix zc.gen` after changing the Manifest.\n"
  import Phoenix.Component, only: [assign: 3]
  alias ZeroCoupledWeb.PortalPage.Session

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

  def intent_owner(:set_line_quantity) do
    {ZeroCoupled.Features.OrderLines.Intents, :set_line_quantity}
  end

  def intent_owner(:remove_line) do
    {ZeroCoupled.Features.OrderLines.Intents, :remove_line}
  end

  def intent_owner(:undo_remove) do
    {ZeroCoupled.Features.Undo.Intents, :undo_remove}
  end

  def intent_owner(:go_review) do
    {ZeroCoupled.Features.PortalSubmit.Intents, :go_review}
  end

  def intent_owner(:edit_lines) do
    {ZeroCoupled.Features.PortalSubmit.Intents, :edit_lines}
  end

  def intent_owner(name) do
    raise ArgumentError,
          "unknown intent #{inspect(name)} — declare it with `intent` in a feature's Intents module"
  end

  (
    @doc "Fact modules the manifest declares a reaction for."
    def declared_facts do
      [
        ZeroCoupled.Features.OrderLines.Facts.LineRemoved,
        ZeroCoupled.Features.Undo.Facts.ItemRestored,
        ZeroCoupled.Features.Undo.Facts.RemovalFinal,
        ZeroCoupled.Foundation.Broadcast.Facts.StockChanged
      ]
    end
  )

  def apply_fact(session, %ZeroCoupled.Features.OrderLines.Facts.LineRemoved{} = fact) do
    effects = []

    (
      payload = (&%{item: &1.line, item_id: &1.line_id}).(fact)

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
        ZeroCoupled.Features.OrderLines.Intents.receive_line(Map.fetch!(session, :order), payload)

      session = Map.replace!(session, :order, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(session, %ZeroCoupled.Features.Undo.Facts.RemovalFinal{} = fact) do
    effects = []

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.OrderLines.Intents.confirm_removal(
          Map.fetch!(session, :order),
          payload
        )

      session = Map.replace!(session, :order, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(session, %ZeroCoupled.Foundation.Broadcast.Facts.StockChanged{} = fact) do
    effects = []

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.OrderLines.Intents.set_stock(Map.fetch!(session, :order), payload)

      session = Map.replace!(session, :order, new_slot)
      effects = effects ++ more
    )

    (
      payload = Map.from_struct(fact)

      {new_slot, more} =
        ZeroCoupled.Features.PortalCatalog.Intents.set_stock(
          Map.fetch!(session, :catalog),
          payload
        )

      session = Map.replace!(session, :catalog, new_slot)
      effects = effects ++ more
    )

    {session, effects}
  end

  def apply_fact(_session, fact) do
    raise ArgumentError,
          "undeclared fact #{inspect(fact)} — add a `react` entry to the page Manifest"
  end

  def page_event("set_line_quantity", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, item_id: :int, quantity: :int)

    run.(socket, fn session ->
      ZeroCoupled.Features.OrderLines.Intents.set_line_quantity(session, args)
    end)
  end

  def page_event("remove_line", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, item_id: :int)

    run.(socket, fn session ->
      ZeroCoupled.Features.OrderLines.Intents.remove_line(session, args)
    end)
  end

  def page_event("undo_remove", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, [])
    run.(socket, fn session -> ZeroCoupled.Features.Undo.Intents.undo_remove(session, args) end)
  end

  def page_event("go_review", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, [])

    run.(socket, fn session ->
      ZeroCoupled.Features.PortalSubmit.Intents.go_review(session, args)
    end)
  end

  def page_event("edit_lines", params, socket, run) do
    args = ZeroCoupledWeb.PageCheck.cast_params(params, [])

    run.(socket, fn session ->
      ZeroCoupled.Features.PortalSubmit.Intents.edit_lines(session, args)
    end)
  end

  def page_event(event, _params, _socket, _run) do
    raise ArgumentError,
          "unknown event #{inspect(event)} — declare an `intent` or add a hand-written handle_event clause"
  end

  def page_render(assigns) do
    ZeroCoupledWeb.PortalLive.PortalView.render(assigns)
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
      stale_order = render_stale?(socket, :order_slot, Map.fetch!(session, :order))
      stale_undo = render_stale?(socket, :undo_slot, Map.fetch!(session, :undo))
      stale_flow = render_stale?(socket, :flow_slot, Map.fetch!(session, :flow))

      socket =
        socket
        |> assign(:session, session)
        |> assign(:order_slot, Map.fetch!(session, :order))
        |> assign(:catalog_slot, Map.fetch!(session, :catalog))
        |> assign(:undo_slot, Map.fetch!(session, :undo))
        |> assign(:flow_slot, Map.fetch!(session, :flow))

      socket =
        if stale_order do
          assign(
            socket,
            :order,
            ZeroCoupled.Features.OrderLines.render_data(Map.fetch!(session, :order))
          )
        else
          socket
        end

      socket =
        if stale_undo do
          assign(socket, :undo, ZeroCoupled.Features.Undo.render_data(Map.fetch!(session, :undo)))
        else
          socket
        end

      socket =
        if stale_flow do
          assign(
            socket,
            :flow,
            ZeroCoupled.Features.PortalSubmit.render_data(Map.fetch!(session, :flow))
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
    @doc "Milestone steps + labels for the wizard chrome."
    def flow_milestones(:bulk_order) do
      [lines: "Order", review: "Review", submitted: "Done"]
    end
  )

  def flow_path(:bulk_order, :lines) do
    "/portal"
  end

  def flow_path(:bulk_order, :review) do
    "/portal/review"
  end

  def flow_path(:bulk_order, :submitted) do
    "/portal/submitted"
  end

  (
    @doc "URL for a flow step; nil for steps without one (no patch emitted)."
    def flow_path(_flow, _step) do
      nil
    end
  )

  (
    @doc "Resolve handle_params to a flow step: no segment means the initial\nstep; only URL-addressable (path-bearing) steps resolve; anything\nelse is nil (ignore).\n"
    def flow_param_step(:bulk_order, params) do
      case params["step"] do
        nil ->
          :lines

        step ->
          Map.get(%{"lines" => :lines, "review" => :review, "submitted" => :submitted}, step)
      end
    end
  )

  (
    @doc false
    def __manifest__ do
      %{
        action_views: [index: ZeroCoupledWeb.PortalLive.PortalView],
        features: [
          {:order, ZeroCoupled.Features.OrderLines,
           render: :render_data,
           config: [
             pricing: [
               shipping: %{
                 express: %{cost: 1299, free_above: nil, label: "Express (2–3 days)"},
                 overnight: %{cost: 2499, free_above: nil, label: "Overnight"},
                 standard: %{cost: 599, free_above: 5000, label: "Standard (5–7 days)"}
               },
               volume_tiers: [
                 {200_000, 10, "10% volume discount"},
                 {50000, 5, "5% volume discount"}
               ]
             ]
           ]},
          {:catalog, ZeroCoupled.Features.PortalCatalog, []},
          {:undo, ZeroCoupled.Features.Undo, render: :render_data, config: [window_ms: 5000]},
          {:flow, ZeroCoupled.Features.PortalSubmit, render: :render_data}
        ],
        intents: [
          {:set_line_quantity, :order, ZeroCoupled.Features.OrderLines.Intents,
           item_id: :int, quantity: :int},
          {:remove_line, :order, ZeroCoupled.Features.OrderLines.Intents, item_id: :int},
          {:undo_remove, :undo, ZeroCoupled.Features.Undo.Intents, []},
          {:go_review, :flow, ZeroCoupled.Features.PortalSubmit.Intents, []},
          {:edit_lines, :flow, ZeroCoupled.Features.PortalSubmit.Intents, []}
        ],
        reactions: [
          {ZeroCoupled.Features.OrderLines.Facts.LineRemoved,
           [{:undo, ZeroCoupled.Features.Undo.Intents, :capture_removed, transform: true}]},
          {ZeroCoupled.Features.Undo.Facts.ItemRestored,
           [{:order, ZeroCoupled.Features.OrderLines.Intents, :receive_line, transform: false}]},
          {ZeroCoupled.Features.Undo.Facts.RemovalFinal,
           [{:order, ZeroCoupled.Features.OrderLines.Intents, :confirm_removal, transform: false}]},
          {ZeroCoupled.Foundation.Broadcast.Facts.StockChanged,
           [
             {:order, ZeroCoupled.Features.OrderLines.Intents, :set_stock, transform: false},
             {:catalog, ZeroCoupled.Features.PortalCatalog.Intents, :set_stock, transform: false}
           ]}
        ]
      }
    end
  )
end
