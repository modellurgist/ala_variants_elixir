defmodule ZeroCoupled.Credo.ComponentPurityRules do
  @moduledoc """
  V32 presentation-layer conformance rules — the detection engine, with **no
  Credo dependency** so it can run as a standalone measurement instrument
  (`run_component_purity.exs`) as well as behind the Credo check
  (`component_purity.ex`).

  This is `CorePurity` inverted. `CorePurity` proves the *core* never touches
  the web; these rules prove the *presentation* never touches the domain, its
  peers, or raw string contracts — the surface `CorePurity` deliberately prunes
  (`credo/core_purity.ex:52-59`, the `*.Components` carve-out).

  Two detection strategies, because a LiveView module is two languages in one
  file:

    * **AST walk** (`domain_findings/1`) for real Elixir — `alias`/`import`/
      fully-qualified references to domain modules. Same `__aliases__` traversal
      `CorePurity` uses, with an inverted forbidden set.
    * **Line scan** (`contract_findings/1`) for everything inside a `~H"""`
      heredoc. HEEx is a **compile-time sigil**: in the module's AST the whole
      template is one opaque string binary, so `phx-click="…"`, `@a.b.c` reads,
      and `phx-hook="…"` are invisible to `Code.string_to_quoted/1`. The checker
      must treat markup as text. (That opacity is itself an argument for moving
      contracts *out* of markup into ports, where the AST can see them.)

  Rules (each finding is tagged with its `:rule`, so the runner can tally):

    * `:domain_ref`   — presentation references a domain module.
    * `:domain_shape` — a `@a.b.c` reach into nested domain shape (advisory).
    * `:event_string` — a hardcoded `phx-click/change/submit=\"literal\"` intent
                        name (should be an interpolated event *port*).
    * `:dom_contract` — a literal `phx-hook=` or a stream container `id=` (should
                        derive from a single-sourced contracts module).
  """

  @type finding :: %{rule: atom(), line: pos_integer(), message: String.t(), trigger: String.t()}

  # Domain prefixes the presentation layer must not depend on. `ZeroCoupledWeb`,
  # `Phoenix.*`, `Money`, core_components and `~p` routes are platform knowledge
  # (§109) and are NOT here — depending on them extends the language, it is not
  # peer coupling. A `*.Components` peer is presentation, so it is carved out.
  @forbidden_domain_prefixes [
    [:ZeroCoupled, :Cart],
    [:ZeroCoupled, :Domain],
    [:ZeroCoupled, :Foundation],
    [:ZeroCoupled, :Features]
  ]

  @events ~w(click change submit keyup keydown keypress blur focus)

  @doc "All findings for one presentation file."
  @spec findings(String.t(), String.t()) :: [finding()]
  def findings(_filename, source) do
    domain_findings(source) ++ contract_findings(source)
  end

  # ── AST: domain-module references ────────────────────────────────────────
  # `scope: :components_only` restricts the walk to `defmodule *.Components`
  # subtrees — needed for feature files, where the pure Intents/Facts siblings
  # legitimately reference the domain (they are governed by CorePurity, and a
  # whole-file walk would flag them; a migration finding the spike's
  # hand-picked file list never hit).
  @spec domain_findings(String.t(), :all | :components_only) :: [finding()]
  def domain_findings(source, scope \\ :all) do
    case Code.string_to_quoted(source, columns: true) do
      {:ok, ast} ->
        {_ast, acc} =
          case scope do
            :all -> Macro.prewalk(ast, [], &collect_domain_ref/2)
            :components_only -> Macro.prewalk(ast, [], &collect_in_components/2)
          end

        Enum.reverse(acc)

      {:error, _} ->
        []
    end
  end

  # Descend only into `defmodule <X>.Components do ... end` subtrees.
  defp collect_in_components({:defmodule, _, [{:__aliases__, _, parts} | _]} = node, acc)
       when is_list(parts) do
    if List.last(parts) == :Components do
      {_node, inner} = Macro.prewalk(node, [], &collect_domain_ref/2)
      # Prune: findings collected; do not re-descend.
      {{:__block__, [], []}, inner ++ acc}
    else
      {node, acc}
    end
  end

  defp collect_in_components(node, acc), do: {node, acc}

  defp collect_domain_ref({:__aliases__, meta, parts} = node, acc)
       when is_list(parts) do
    if forbidden_domain?(parts) do
      path = Enum.map_join(parts, ".", &to_string/1)

      finding = %{
        rule: :domain_ref,
        line: meta[:line] || 0,
        message: "presentation references domain module #{path}",
        trigger: path
      }

      {node, [finding | acc]}
    else
      {node, acc}
    end
  end

  defp collect_domain_ref(node, acc), do: {node, acc}

  # Forbidden iff the alias path starts with a domain prefix AND is not a
  # presentation peer (`*.Components`). Matches on the *literal* path the way
  # `CorePurity` does; a shortened aliased call (`Wishlist.member?`) is caught at
  # its `alias` line rather than the call site — enough to flag the dependency.
  defp forbidden_domain?(parts) do
    not Enum.member?(parts, :Components) and
      Enum.any?(@forbidden_domain_prefixes, &List.starts_with?(parts, &1))
  end

  # ── AST: non-markup contract call sites (Enhancement A) ──────────────────
  # The V32 markup rules only see `~H` templates. The *same* string/atom
  # contracts are also restated in ordinary Elixir — effect emitters
  # (`Effects.push("item-removed")`, `Effects.stream_insert(:cart_items, …)`)
  # and cross-process message patterns (`handle_info({:stock_changed, …})`).
  # These are real AST, so they are caught precisely (no line scan).
  #
  #   * `:contract_literal` — a literal event/stream name at an effect call site
  #                          that should come from `Web.Contracts`.
  #   * `:pubsub_tuple`     — an untyped tagged-tuple message (a stringly/atom
  #                          contract that fails *silently* on drift — the
  #                          highest-value leak; motivates the manifest-routed
  #                          typed-fact fix, Enhancement B).
  @spec call_site_findings(String.t()) :: [finding()]
  def call_site_findings(source) do
    case Code.string_to_quoted(source, columns: true) do
      {:ok, ast} ->
        {_, acc} = Macro.prewalk(ast, [], &collect_call_site/2)
        Enum.reverse(acc)

      {:error, _} ->
        []
    end
  end

  # Effects.push/stream_* with a literal contract as the first argument.
  defp collect_call_site(
         {{:., _, [{:__aliases__, _, parts}, fun]}, meta, [first | _]} = node,
         acc
       )
       when fun in [:push, :stream_insert, :stream_delete, :stream_reset] and is_list(parts) do
    if List.last(parts) == :Effects and literal_contract?(fun, first) do
      {node,
       [
         %{
           rule: :contract_literal,
           line: meta[:line] || 0,
           message: "Effects.#{fun}(#{inspect(first)}, …) restates a contract literal — use Web.Contracts",
           trigger: inspect(first)
         }
         | acc
       ]}
    else
      {node, acc}
    end
  end

  # handle_info clause matched on an atom-tagged tuple: an untyped cross-process
  # (or self-send) message contract.
  defp collect_call_site({def_kw, _, [{:handle_info, meta, [pattern, _socket]} | _]} = node, acc)
       when def_kw in [:def, :defp] do
    case tagged_tuple_tag(pattern) do
      nil ->
        {node, acc}

      tag ->
        {node,
         [
           %{
             rule: :pubsub_tuple,
             line: meta[:line] || 0,
             message: "handle_info matches untyped tagged tuple {#{inspect(tag)}, …} — route a typed fact via the manifest",
             trigger: inspect(tag)
           }
           | acc
         ]}
    end
  end

  defp collect_call_site(node, acc), do: {node, acc}

  defp literal_contract?(:push, first), do: is_binary(first)
  defp literal_contract?(_stream, first), do: is_atom(first)

  # `{:{}, _, [tag | _]}` = a 3+-tuple; a raw 2-tuple is `{tag, _}` in quoted
  # form. Either way the tag must be a bare atom (module-tagged messages like
  # `{SomeModule, _}` are excluded — the first element is an `__aliases__`).
  defp tagged_tuple_tag({:{}, _, [tag | _]}) when is_atom(tag), do: tag
  defp tagged_tuple_tag({tag, _}) when is_atom(tag), do: tag
  defp tagged_tuple_tag(_), do: nil

  # ── Line scan: HEEx string contracts ─────────────────────────────────────
  # Scan ONLY inside `~H"""` heredocs. A contract (event name, hook, stream id,
  # domain-shape read) only matters in markup; scanning comments/docstrings/
  # `@moduledoc` would count prose that merely *describes* the couplings. This
  # also encodes the finding that HEEx is an opaque string to the AST — the
  # markup must be recovered as text, but only the markup.
  @spec contract_findings(String.t()) :: [finding()]
  def contract_findings(source) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> scan_heex_lines(false, [])
  end

  # Track whether we are inside a `~H"""` heredoc; only scan interior lines.
  defp scan_heex_lines([], _inside, acc), do: Enum.reverse(acc)

  defp scan_heex_lines([{line, _n} | rest], false, acc) do
    if String.contains?(line, ~s(~H""")),
      do: scan_heex_lines(rest, true, acc),
      else: scan_heex_lines(rest, false, acc)
  end

  defp scan_heex_lines([{line, n} | rest], true, acc) do
    if Regex.match?(~r/^\s*"""\s*$/, line) do
      scan_heex_lines(rest, false, acc)
    else
      scan_heex_lines(rest, true, Enum.reverse(line_findings(line, n)) ++ acc)
    end
  end

  @event_re ~r/phx-(#{Enum.join(@events, "|")})="([^"{}]+)"/
  @hook_re ~r/phx-hook="([^"{}]+)"/
  @shape_re ~r/@[a-z_]+\.[a-z_]+\.[a-z_]+/

  defp line_findings(line, n) do
    events =
      for [_, ev, name] <- Regex.scan(@event_re, line) do
        %{
          rule: :event_string,
          line: n,
          message: "hardcoded intent string phx-#{ev}=\"#{name}\" — pass an event port instead",
          trigger: name
        }
      end

    hooks =
      for [_, hook] <- Regex.scan(@hook_re, line) do
        %{
          rule: :dom_contract,
          line: n,
          message: "literal phx-hook=\"#{hook}\" — source it from a contracts module",
          trigger: hook
        }
      end

    stream_ids =
      if String.contains?(line, ~s(phx-update="stream")) and Regex.match?(~r/\bid="[^"{}]+"/, line) do
        [id] = Regex.run(~r/\bid="([^"{}]+)"/, line, capture: :all_but_first)

        [
          %{
            rule: :dom_contract,
            line: n,
            message: "literal stream container id=\"#{id}\" — derive it from the slot/contracts",
            trigger: id
          }
        ]
      else
        []
      end

    shapes =
      for match <- Regex.scan(@shape_re, line) |> List.flatten() do
        %{
          rule: :domain_shape,
          line: n,
          message: "deep domain-shape read #{match} — take a projected port value (advisory)",
          trigger: match
        }
      end

    events ++ hooks ++ stream_ids ++ shapes
  end
end
