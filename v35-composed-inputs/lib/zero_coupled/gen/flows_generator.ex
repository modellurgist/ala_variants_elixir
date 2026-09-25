defmodule ZeroCoupled.Gen.FlowsGenerator do
  @moduledoc """
  The V33 flows channel: reads each manifest's `flows/0` (named UI-event state
  machines) and emits the one merged `ZeroCoupled.Flows` core module —
  `initial/1`, `advance/3`, `steps/1` — pure data, no web knowledge, so
  features consume it as a neutral downward dependency. `PageGenerator` calls
  `flows/1` to fold the per-page web-side flow glue; `mix zc.gen` calls
  `flows_source/1` for the merged core module.
  """

  @flows_path "lib/zero_coupled/flows.ex"

  @doc "Where the merged core flows module lives."
  def flows_path, do: @flows_path

  @doc """
  A manifest's validated flow declarations as `[{name, cfg}]`, or `[]` when it
  declares none. Shared by the page generator (web glue) and the core emitter.
  """
  def flows(manifest_mod) do
    if function_exported?(manifest_mod, :flows, 0),
      do: Enum.map(manifest_mod.flows(), &validate_flow!(manifest_mod, &1)),
      else: []
  end

  @doc """
  Source for the merged `ZeroCoupled.Flows` core module, or `nil` when no
  page declares flows. Flow names must be app-unique across pages.
  """
  @spec flows_source([module()]) :: String.t() | nil
  def flows_source(pages) do
    flows =
      for page <- pages,
          manifest_mod = Module.concat(page, Manifest),
          {:module, _} = Code.ensure_loaded(manifest_mod),
          {name, cfg} <- flows(manifest_mod) do
        {name, cfg, manifest_mod}
      end

    flows
    |> Enum.group_by(fn {name, _, _} -> name end)
    |> Enum.each(fn {name, decls} ->
      if length(decls) > 1 do
        mods = Enum.map(decls, fn {_, _, m} -> inspect(m) end)
        raise "flow #{inspect(name)} is declared by multiple manifests: #{Enum.join(mods, ", ")}"
      end
    end)

    if flows == [] do
      nil
    else
      body =
        quote do
          defmodule ZeroCoupled.Flows do
            @moduledoc """
            Merged UI-event flow tables from every page manifest — the one
            neutral module features may consult for their own flow's
            transitions. Pure data; no web knowledge.
            """
            unquote_splicing(flows_core_forms(flows))
          end
        end
        |> Macro.to_string()
        |> Code.format_string!()
        |> IO.iodata_to_binary()

      manifests = Enum.map_join(flows, ", ", fn {_, _, m} -> inspect(m) end)

      """
      # ══════════════════════════════════════════════════════════════════════
      # GENERATED FILE — do not edit.
      # Source of truth: the `flows/0` channel of #{manifests}
      # (change a manifest first, then run `mix zc.gen`).
      # ══════════════════════════════════════════════════════════════════════
      """ <> body <> "\n"
    end
  end

  defp validate_flow!(manifest_mod, {name, cfg}) when is_atom(name) and is_list(cfg) do
    initial = Keyword.get(cfg, :initial) || raise "flow #{inspect(name)} needs :initial (#{inspect(manifest_mod)})"
    transitions = Keyword.get(cfg, :transitions, [])

    Enum.each(transitions, fn
      {from, event, to} when is_atom(from) and is_atom(event) and is_atom(to) -> :ok
      other -> raise "flow #{inspect(name)}: bad transition #{inspect(other)} (want {from, event, to})"
    end)

    steps = flow_steps(initial, transitions)

    for {step, _path} <- Keyword.get(cfg, :paths, []), step not in steps do
      raise "flow #{inspect(name)}: path for unknown step #{inspect(step)}"
    end

    {name, cfg}
  end

  # Declared steps, in appearance order: initial first, then transition ends.
  defp flow_steps(initial, transitions) do
    Enum.uniq([initial | Enum.flat_map(transitions, fn {from, _e, to} -> [from, to] end)])
  end

  defp flows_core_forms(flows) do
    initials =
      for {name, cfg, _m} <- flows do
        quote do
          def initial(unquote(name)), do: unquote(Keyword.fetch!(cfg, :initial))
        end
      end

    initial_fallback =
      quote do
        def initial(flow), do: raise(ArgumentError, "unknown flow #{inspect(flow)}")
      end

    advances =
      for {name, cfg, _m} <- flows,
          {from, event, to} <- Keyword.get(cfg, :transitions, []) do
        quote do
          def advance(unquote(name), unquote(from), unquote(event)), do: unquote(to)
        end
      end

    advance_fallbacks =
      for {name, _cfg, _m} <- flows do
        quote do
          def advance(unquote(name), _from, _event), do: :no_transition
        end
      end

    advance_raise =
      quote do
        def advance(flow, _from, _event), do: raise(ArgumentError, "unknown flow #{inspect(flow)}")
      end

    steps =
      for {name, cfg, _m} <- flows do
        list = flow_steps(Keyword.fetch!(cfg, :initial), Keyword.get(cfg, :transitions, []))

        quote do
          def steps(unquote(name)), do: unquote(list)
        end
      end

    steps_fallback =
      quote do
        def steps(flow), do: raise(ArgumentError, "unknown flow #{inspect(flow)}")
      end

    initials ++
      [initial_fallback] ++ advances ++ advance_fallbacks ++ [advance_raise] ++ steps ++ [steps_fallback]
  end
end
