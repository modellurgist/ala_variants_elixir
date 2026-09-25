defmodule ZeroCoupled.Gen.PageGenerator do
  @moduledoc """
  V30's "diagram compiler" — the same code V29's `@before_compile` ran,
  retargeted from `quote`-injection to **writing a committed file**.

  Given a page module (e.g. `ZeroCoupledWeb.CartPage`), it reads that
  page's `Manifest` (a plain data module) and emits the glue — a Session
  struct, pure runners, one straight-line `apply_fact/2` clause per
  react entry, one `page_event/4` clause per declared intent, render
  dispatch, and per-slot assigns — as ordinary Elixir source, formatted
  with `Code.format_string!/1`.

  Two inputs, two channels:

    * **Runtime introspection** for everything that is plain data —
      `Manifest.features/0` and `Manifest.action_views/0` (module
      aliases already resolved by the compiler) and each feature's
      `Intents.__intents__/0`.
    * **The manifest file's AST** (`Code.string_to_quoted!/1`) for the
      one thing runtime data cannot carry: the source of a react
      target's `transform:` capture, spliced verbatim into the generated
      `apply_fact/2` clause exactly as V29's macro spliced it.

  The output is *exactly the code you would write by hand* — now
  reviewed in PRs like any other file. `mix zc.gen --check` fails the
  build if the committed file drifts from this generator's output.
  """

  alias ZeroCoupled.Gen.{FlowsGenerator, ManifestResolver}

  # ── Public API ────────────────────────────────────────────────────────

  @doc "Return the full formatted source for `page_module`'s generated file."
  @spec generate(module()) :: String.t()
  def generate(page_module) do
    manifest_mod = Module.concat(page_module, Manifest)
    Code.ensure_loaded!(manifest_mod)

    features = ManifestResolver.normalize_features(manifest_mod.features())
    if features == [], do: raise("Manifest #{inspect(manifest_mod)} must declare at least one feature")

    reactions = ManifestResolver.resolve_reactions(manifest_mod)
    action_views = manifest_mod.action_views()
    intents = ManifestResolver.collect_intents!(features)
    flows = FlowsGenerator.flows(manifest_mod)

    session_mod = Module.concat(page_module, Session)
    generated_mod = Module.concat(page_module, Generated)

    body =
      [
        session_module(session_mod, features),
        generated_module(generated_mod, session_mod, features, reactions, action_views, intents, flows)
      ]
      |> Enum.map_join("\n\n", &Macro.to_string/1)
      |> Code.format_string!()
      |> IO.iodata_to_binary()

    header(manifest_mod) <> body <> "\n"
  end

  @doc "Where `page_module`'s generated file lives (next to its source)."
  @spec generated_path(module()) :: String.t()
  def generated_path(page_module) do
    src = page_module.module_info(:compile)[:source] |> to_string()
    Path.join(Path.rootname(src), "generated.ex")
  end

  # ── Generated modules ─────────────────────────────────────────────────

  defp session_module(session_mod, features) do
    slots = for {slot, _mod, _opts} <- features, do: {slot, nil}

    # A slot's `config:` (manifest calibration — V34) is spliced into its
    # init opts at generation time, so the values live on the diagram and
    # each abstraction stays generic. Slots without config init as before.
    inits =
      for {slot, mod, opts} <- features do
        init_call =
          case Keyword.get(opts, :config) do
            nil ->
              quote(do: unquote(mod).init(opts))

            cfg ->
              quote(do: unquote(mod).init(Keyword.put(opts, :config, unquote(Macro.escape(cfg)))))
          end

        {slot, init_call}
      end

    quote do
      defmodule unquote(session_mod) do
        @moduledoc "Generated session struct: one field per manifest slot."
        defstruct unquote(slots)

        def new(opts \\ []) do
          struct!(__MODULE__, unquote(inits))
        end
      end
    end
  end

  defp generated_module(generated_mod, session_mod, features, reactions, action_views, intents, flows) do
    forms =
      runner_forms() ++
        intent_owner_forms(intents) ++
        apply_fact_forms(reactions) ++
        page_event_forms(intents) ++
        page_render_forms(action_views) ++
        session_helper_forms(features) ++
        flow_web_forms(flows) ++
        manifest_forms(features, reactions, action_views, intents)

    quote do
      defmodule unquote(generated_mod) do
        @moduledoc """
        Generated glue for the page. **Do not edit** — regenerate with
        `mix zc.gen` after changing the Manifest.
        """
        import Phoenix.Component, only: [assign: 3]
        alias unquote(session_mod)

        unquote_splicing(forms)
      end
    end
  end

  # Pure runners — identical semantics to V29.1 (no socket, no effects I/O).
  defp runner_forms do
    [
      quote do
        @doc "Pure runner: an intent closure → its facts → `{session, effects}`."
        def run_pure(session, fun) when is_function(fun, 1) do
          case fun.(session) do
            {session, effects} -> apply_facts(session, effects, [])
            {session, effects, facts} -> apply_facts(session, effects, facts)
          end
        end
      end,
      quote do
        @doc "Pure runner by intent name or `{module, function}`."
        def run_intent(session, name, args) when is_atom(name),
          do: run_intent(session, intent_owner(name), args)
      end,
      quote do
        def run_intent(session, {mod, fun}, args),
          do: run_pure(session, fn session -> apply(mod, fun, [session, args]) end)
      end,
      quote do
        defp apply_facts(session, effects, facts) do
          Enum.reduce(facts, {session, effects}, fn fact, {session, effects} ->
            {session, more} = apply_fact(session, fact)
            {session, effects ++ more}
          end)
        end
      end
    ]
  end

  defp intent_owner_forms(intents) do
    clauses =
      for {name, _slot, mod, _params} <- intents do
        quote do
          def intent_owner(unquote(name)), do: {unquote(mod), unquote(name)}
        end
      end

    fallback =
      quote do
        def intent_owner(name) do
          raise ArgumentError,
                "unknown intent #{inspect(name)} — declare it with `intent` in a feature's Intents module"
        end
      end

    clauses ++ [fallback]
  end

  # One straight-line clause per react entry — single level, no cascade.
  # Reactions receive `Map.from_struct(fact)` or the transform's result,
  # never the emitter's struct.
  #
  # `declared_facts/0` lets the page's generic handle_info forward only
  # *declared* fact structs (cross-process facts arrive over PubSub as the
  # same structs the manifest wires; undeclared structs fall through
  # instead of hitting apply_fact's loud raise).
  defp apply_fact_forms(reactions) do
    fact_mods = Enum.map(reactions, &elem(&1, 0))

    declared =
      quote do
        @doc "Fact modules the manifest declares a reaction for."
        def declared_facts, do: unquote(fact_mods)
      end

    clauses =
      [declared | for({fact_mod, targets} <- reactions, do: apply_fact_clause(fact_mod, targets))]

    fallback =
      quote do
        def apply_fact(_session, fact) do
          raise ArgumentError,
                "undeclared fact #{inspect(fact)} — add a `react` entry to the page Manifest"
        end
      end

    clauses ++ [fallback]
  end

  defp apply_fact_clause(fact_mod, targets) do
    steps = Enum.map(targets, &apply_fact_step/1)

    quote do
      def apply_fact(session, %unquote(fact_mod){} = fact) do
        effects = []
        unquote_splicing(steps)
        {session, effects}
      end
    end
  end

  defp apply_fact_step(%{slot: slot, mod: mod, fun: fun, transform_ast: transform_ast}) do
    payload_ast =
      if transform_ast,
        do: quote(do: unquote(transform_ast).(fact)),
        else: quote(do: Map.from_struct(fact))

    quote do
      payload = unquote(payload_ast)
      {new_slot, more} = unquote(mod).unquote(fun)(Map.fetch!(session, unquote(slot)), payload)
      session = Map.replace!(session, unquote(slot), new_slot)
      effects = effects ++ more
    end
  end

  # One event clause per declared intent (param casts included). The 4th
  # argument is the page's `run/2` — the only house pattern, passed in so
  # the generated module stays free of socket/effect configuration.
  defp page_event_forms(intents) do
    clauses =
      for {name, _slot, mod, params} <- intents do
        event = Atom.to_string(name)

        quote do
          def page_event(unquote(event), params, socket, run) do
            args = ZeroCoupledWeb.PageCheck.cast_params(params, unquote(params))
            run.(socket, fn session -> unquote(mod).unquote(name)(session, args) end)
          end
        end
      end

    fallback =
      quote do
        def page_event(event, _params, _socket, _run) do
          raise ArgumentError,
                "unknown event #{inspect(event)} — declare an `intent` or add a hand-written handle_event clause"
        end
      end

    clauses ++ [fallback]
  end

  defp page_render_forms(action_views) do
    index_view =
      case List.keyfind(action_views, :index, 0) do
        {_, view} -> view
        nil -> raise "a Manifest must declare `index:` in action_views/0"
      end

    exact =
      for {action, view} <- action_views, action != :index do
        quote do
          def page_render(%{live_action: unquote(action)} = assigns),
            do: unquote(view).render(assigns)
        end
      end

    exact ++ [quote(do: def(page_render(assigns), do: unquote(index_view).render(assigns)))]
  end

  # Per-slot assigns: templates read `@cart_slot`, `@wishlist_slot`, …
  # Structural sharing makes an untouched slot the same term, so its
  # `assign/3` is an equality no-op and LiveView skips that feature's
  # template regions and call sites.
  #
  # A render_data slot (`render:`) is additionally *gated*: its `@cart`
  # assign is recomputed only when the cart slot's term actually changed
  # (O(1) identity check) — so an event that touches only another feature
  # does no cart presentation work at all.
  defp session_helper_forms(features) do
    slot_assigns =
      for {slot, _mod, _opts} <- features do
        name = String.to_atom("#{slot}_slot")
        quote(do: assign(unquote(name), Map.fetch!(session, unquote(slot))))
      end

    render_slots =
      for {slot, mod, opts} <- features, fun = opts[:render], fun != nil, do: {slot, mod, fun}

    base_pipe =
      [quote(do: assign(:session, session)) | slot_assigns]
      |> Enum.reduce(quote(do: socket), fn call, acc -> quote(do: unquote(acc) |> unquote(call)) end)

    put_body = put_session_body(base_pipe, render_slots)

    forms = [
      quote do
        @doc "Initialize the session (and timers) into assigns at mount."
        def mount_session(socket, opts \\ []) do
          socket |> assign(:timers, %{}) |> put_session(Session.new(opts))
        end
      end,
      quote do
        @doc "Assign a new session: per-slot assigns plus any gated render_data slots."
        def put_session(socket, session) do
          unquote_splicing(put_body)
        end
      end
    ]

    forms ++ render_stale_helper(render_slots)
  end

  # No render slots: put_session is just the assign pipe. Otherwise capture
  # each render slot's staleness *before* the pipe overwrites its slot
  # assign, then conditionally recompute the presentation assign after.
  defp put_session_body(base_pipe, []), do: [base_pipe]

  defp put_session_body(base_pipe, render_slots) do
    gates =
      for {slot, _mod, _fun} <- render_slots do
        slot_key = String.to_atom("#{slot}_slot")

        quote do
          unquote(gate_var(slot)) =
            render_stale?(socket, unquote(slot_key), Map.fetch!(session, unquote(slot)))
        end
      end

    renders =
      for {slot, mod, fun} <- render_slots do
        quote do
          socket =
            if unquote(gate_var(slot)),
              do:
                assign(
                  socket,
                  unquote(slot),
                  unquote(mod).unquote(fun)(Map.fetch!(session, unquote(slot)))
                ),
              else: socket
        end
      end

    gates ++ [quote(do: (socket = unquote(base_pipe)))] ++ renders ++ [quote(do: socket)]
  end

  defp gate_var(slot), do: Macro.var(:"stale_#{slot}", nil)

  defp render_stale_helper([]), do: []

  defp render_stale_helper(_render_slots) do
    [
      quote do
        # Recompute a render_data assign only when its slot term changed.
        # Structural sharing makes this an O(1) identity check; a false
        # "stale" costs only a harmless recompute, never a skipped one.
        defp render_stale?(socket, slot_key, value) do
          case socket.assigns do
            %{^slot_key => prev} -> not :erts_debug.same(prev, value)
            _ -> true
          end
        end
      end
    ]
  end

  # Web-side flow glue: wizard chrome data, step→URL, and URL→step. The
  # transition table itself lives in the core `ZeroCoupled.Flows`.
  defp flow_web_forms([]), do: []

  defp flow_web_forms(flows) do
    milestones =
      for {name, cfg} <- flows do
        quote do
          @doc "Milestone steps + labels for the wizard chrome."
          def flow_milestones(unquote(name)), do: unquote(Keyword.get(cfg, :milestones, []))
        end
      end

    paths =
      for {name, cfg} <- flows, {step, path} <- Keyword.get(cfg, :paths, []) do
        quote do
          def flow_path(unquote(name), unquote(step)), do: unquote(path)
        end
      end

    path_fallback =
      quote do
        @doc "URL for a flow step; nil for steps without one (no patch emitted)."
        def flow_path(_flow, _step), do: nil
      end

    params =
      for {name, cfg} <- flows do
        initial = Keyword.fetch!(cfg, :initial)

        step_map =
          cfg |> Keyword.get(:paths, []) |> Map.new(fn {step, _} -> {Atom.to_string(step), step} end)

        quote do
          @doc """
          Resolve handle_params to a flow step: no segment means the initial
          step; only URL-addressable (path-bearing) steps resolve; anything
          else is nil (ignore).
          """
          def flow_param_step(unquote(name), params) do
            case params["step"] do
              nil -> unquote(initial)
              step -> Map.get(unquote(Macro.escape(step_map)), step)
            end
          end
        end
      end

    milestones ++ paths ++ [path_fallback] ++ params
  end

  defp manifest_forms(features, reactions, action_views, intents) do
    manifest_reactions =
      for {fact_mod, targets} <- reactions do
        {fact_mod,
         Enum.map(targets, fn t -> {t.slot, t.mod, t.fun, transform: t.transform_ast != nil} end)}
      end

    manifest = %{
      features: features,
      reactions: manifest_reactions,
      action_views: action_views,
      intents: Enum.map(intents, fn {name, slot, mod, params} -> {name, slot, mod, params} end)
    }

    [
      quote do
        @doc false
        def __manifest__, do: unquote(Macro.escape(manifest))
      end
    ]
  end

  # ── Header ────────────────────────────────────────────────────────────

  defp header(manifest_mod) do
    """
    # ══════════════════════════════════════════════════════════════════════
    # GENERATED FILE — do not edit.
    # Source of truth: #{inspect(manifest_mod)} (change it first, then run
    # `mix zc.gen`). `mix zc.gen --check` fails the build on drift.
    # ══════════════════════════════════════════════════════════════════════
    """
  end
end
