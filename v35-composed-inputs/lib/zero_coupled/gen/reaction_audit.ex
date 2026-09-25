defmodule ZeroCoupled.Gen.ReactionAudit do
  @moduledoc """
  Whole-program audit of **reaction placement** — is each reaction on the
  correct side of the declare-vs-inline amortization crossover?

  Two forms of reaction wire a fact/message to a reactor intent:

    * **declarative** — an entry in a page `Manifest.reactions/0`
      (`{Fact, to: {slot, Intents, fun}}`), expanded into `apply_fact/2`.
    * **imperative** — a hand-written `handle_info`/`handle_async` clause in
      the page module that calls a reactor intent via `run/2`.

  The manifest form is single-level by construction: a reaction returns
  `{slot, effects}`, so it **cannot emit a fact**. That gives an exact,
  mechanical placement rule (no fuzzy "numerous/regular" judgement needed):

    * A **shell** reaction is *correctly imperative* iff it has a forcing
      reason it could not be a single-level manifest wire: it is a
      `handle_async` result, it performs I/O, its target intent **emits a
      fact** (cascade — illegal in a manifest reaction), or it is triggered
      by a non-fact message. Otherwise it is **MISPLACED** — a pure,
      fact-triggered, single-level reactor hand-wired in the shell that
      belongs in `reactions/0`.
    * A **manifest** reaction is *correctly declarative* iff its target does
      **not** emit a fact. A fact-emitting target is a single-level
      violation (its facts are dropped / it crashes) — **MISPLACED**, belongs
      in the shell or must be restructured.

  Whole-program (needs the manifest + every feature + the shell), so it ships
  as an audit task, not a per-file Credo check. Runner: `run_reaction_audit.exs`.
  """

  @foundation ~w(Carts Products Orders Broadcast Repo)a

  @type finding :: %{kind: :shell_misplaced | :manifest_misplaced, where: String.t(), detail: String.t()}

  @doc "Audit a whole variant rooted at `lib/`. Returns {findings, stats}."
  @spec run(String.t()) :: {[finding()], map()}
  def run(lib \\ "lib") do
    emits = fact_emission_map(Path.wildcard(Path.join(lib, "zero_coupled/features/*.ex")))
    pages = Path.wildcard(Path.join(lib, "zero_coupled_web/pages/*.ex"))
    manifests = Path.wildcard(Path.join(lib, "zero_coupled_web/pages/*/manifest.ex"))

    shell = Enum.flat_map(pages, &shell_reactions(&1, emits))
    manifest = Enum.flat_map(manifests, &manifest_reactions(&1, emits))

    findings =
      for r <- shell ++ manifest, r.verdict != :ok do
        %{kind: r.side_misplaced, where: r.where, detail: r.detail}
      end

    stats = %{
      shell_total: length(shell),
      shell_forced: Enum.count(shell, &(&1.verdict == :ok)),
      manifest_total: length(manifest),
      findings: length(findings)
    }

    {findings, stats, shell, manifest}
  end

  # ── Does a reactor intent emit a fact? (the discriminator) ───────────────
  # Map keyed by {feature_name, fun} => bool, over every `*.Intents` function.
  defp fact_emission_map(feature_files) do
    Enum.reduce(feature_files, %{}, fn file, acc ->
      case Code.string_to_quoted(File.read!(file)) do
        {:ok, ast} -> collect_emission(ast, acc)
        _ -> acc
      end
    end)
  end

  defp collect_emission(ast, acc) do
    {_, {_feature, map}} =
      Macro.prewalk(ast, {nil, acc}, fn
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = node, {_f, m} ->
          {node, {intents_feature(parts), m}}

        {def_kw, _, [head | _]} = node, {feature, m} when def_kw in [:def, :defp] and feature != nil ->
          case fun_name(head) do
            nil -> {node, {feature, m}}
            fun -> {node, {feature, Map.update(m, {feature, fun}, emits_fact?(node), &(&1 or emits_fact?(node)))}}
          end

        node, state ->
          {node, state}
      end)

    map
  end

  # Feature name for an `*.Intents` module: the alias part before :Intents.
  defp intents_feature(parts) do
    case Enum.reverse(parts) do
      [:Intents, feature | _] -> to_string(feature)
      _ -> nil
    end
  end

  defp fun_name({name, _, args}) when is_atom(name) and is_list(args), do: name
  defp fun_name({:when, _, [inner | _]}), do: fun_name(inner)
  defp fun_name(_), do: nil

  # A function *emits* a fact iff it returns the 3-tuple `{session, effects,
  # facts}` whose 3rd element carries a `%…Facts…{}` struct. Constructing a
  # Facts struct elsewhere (e.g. as a timer-message payload inside the effects
  # list of a 2-tuple reaction return — `capture_removed`) is NOT emission and
  # must not be flagged. In quoted form a 3+-element tuple is `{:{}, _, elems}`;
  # a 2-tuple is a bare `{a, b}`.
  defp emits_fact?(node) do
    {_, found} =
      Macro.prewalk(node, false, fn
        {:{}, _, [_session, _effects, facts]} = n, acc -> {n, acc or has_fact_struct?(facts)}
        n, acc -> {n, acc}
      end)

    found
  end

  defp has_fact_struct?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:%, _, [{:__aliases__, _, parts}, _]} = n, acc -> {n, acc or Enum.member?(parts, :Facts)}
        n, acc -> {n, acc}
      end)

    found
  end

  # ── Shell reactions: handle_info / handle_async clauses ──────────────────
  defp shell_reactions(page_file, emits) do
    {:ok, ast} = Code.string_to_quoted(File.read!(page_file))
    page = page_name(ast)

    {_, clauses} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{name, _, [pattern, _sock | _]}, [do: body]]} = node, acc
        when name in [:handle_info, :handle_async] ->
          {node, [classify_shell(page, name, pattern, body, emits) | acc]}

        # `def h(a, b), do: …` desugars via keyword; also catch block form
        node, acc ->
          {node, acc}
      end)

    clauses |> Enum.reject(&is_nil/1) |> Enum.reverse()
  end

  defp classify_shell(page, kind, pattern, body, emits) do
    targets = intent_calls(body)
    bridge? = calls?(body, :apply_fact) or targets == []

    cond do
      bridge? ->
        nil

      true ->
        io? = does_io?(body)
        struct_trigger? = match?({:%, _, _}, pattern)
        emitting = Enum.any?(targets, fn {f, fun} -> Map.get(emits, {f, fun}, false) end)
        forced = kind == :handle_async or io? or emitting or not struct_trigger?

        %{
          where: "#{page}.#{kind}",
          side_misplaced: :shell_misplaced,
          detail:
            "→ #{fmt(targets)} " <>
              reason(kind, io?, emitting, struct_trigger?),
          verdict: if(forced, do: :ok, else: :misplaced)
        }
    end
  end

  defp reason(:handle_async, _, _, _), do: "[async result — forced imperative]"
  defp reason(_, true, _, _), do: "[does I/O — forced imperative]"
  defp reason(_, _, true, _), do: "[reactor emits a fact — cannot be single-level; forced imperative]"
  defp reason(_, _, _, false), do: "[non-fact message — forced imperative]"
  defp reason(_, _, _, _), do: "[pure, single-level, fact-triggered — COULD be a manifest reaction]"

  # ── Manifest reactions: reactions/0 targets ──────────────────────────────
  defp manifest_reactions(manifest_file, emits) do
    {:ok, ast} = Code.string_to_quoted(File.read!(manifest_file))
    mod = page_name(ast)
    body = def_body(ast, :reactions)

    (body && targets_in(body))
    |> List.wrap()
    |> Enum.map(fn {feature, fun} ->
      emitting = Map.get(emits, {feature, fun}, false)

      %{
        where: "#{mod}.reactions → #{feature}.#{fun}",
        side_misplaced: :manifest_misplaced,
        detail: if(emitting, do: "reactor emits a fact — single-level violation", else: "single-level"),
        verdict: if(emitting, do: :misplaced, else: :ok)
      }
    end)
  end

  # ── AST helpers ──────────────────────────────────────────────────────────
  defp page_name(ast) do
    {_, name} =
      Macro.prewalk(ast, nil, fn
        {:defmodule, _, [{:__aliases__, _, parts} | _]} = n, nil -> {n, List.last(parts) |> to_string()}
        n, acc -> {n, acc}
      end)

    name || "?"
  end

  # Calls to `<Feature>.Intents.<fun>` anywhere in an expression.
  defp intent_calls(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, parts}, fun]}, _, _} = n, acc when is_atom(fun) ->
          case Enum.reverse(parts) do
            [:Intents, feature | _] -> {n, [{to_string(feature), fun} | acc]}
            _ -> {n, acc}
          end

        n, acc ->
          {n, acc}
      end)

    Enum.uniq(acc)
  end

  defp calls?(ast, fun) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [_, ^fun]}, _, _} = n, _ -> {n, true}
        n, acc -> {n, acc}
      end)

    found
  end

  defp does_io?(ast) do
    {_, found} =
      Macro.prewalk(ast, false, fn
        {:__aliases__, _, parts} = n, acc -> {n, acc or Enum.any?(@foundation, &(&1 in parts))}
        n, acc -> {n, acc}
      end)

    found
  end

  # reactions/0 targets: any tuple whose 2nd elem is an `*.Intents` alias and
  # 3rd is an atom → {slot, Mod, fun[, opts]}. Captures single + list targets.
  defp targets_in(ast) do
    {_, acc} =
      Macro.prewalk(ast, [], fn
        {:{}, _, [_slot, {:__aliases__, _, parts}, fun | _]} = n, acc when is_atom(fun) ->
          case Enum.reverse(parts) do
            [:Intents, feature | _] -> {n, [{to_string(feature), fun} | acc]}
            _ -> {n, acc}
          end

        n, acc ->
          {n, acc}
      end)

    Enum.reverse(acc)
  end

  defp def_body(ast, name) do
    {_, body} =
      Macro.prewalk(ast, nil, fn
        {:def, _, [{^name, _, args}, [do: b]]} = n, nil when args in [nil, []] -> {n, b}
        n, acc -> {n, acc}
      end)

    body
  end

  defp fmt(targets), do: Enum.map_join(targets, ", ", fn {f, fun} -> "#{f}.#{fun}" end)
end
