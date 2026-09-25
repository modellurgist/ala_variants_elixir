defmodule ZeroCoupled.Credo.ContractPurity do
  @moduledoc """
  Enhancement A: the **contract axis**, app-wide. A cross-boundary contract
  (event name, stream name, dom-id, hook, push event) is a contract wherever it
  appears — so unlike `ComponentPurity` (presentation-scoped, coupling axis),
  this check runs over the whole app and flags a restated contract literal in
  *any* file, markup or Elixir.

  Rules (from `ComponentPurityRules`):

    * `:event_string`, `:dom_contract` — literals in `~H` markup (line scan).
    * `:contract_literal` — a literal at an `Effects.push/stream_*` call site
      (AST); the 14 emitter leaks V32's markup rules could not see.
    * `:pubsub_tuple` — an untyped tagged-tuple `handle_info` message (AST); the
      silent-drift leak, motivating Enhancement B.

  The fix for every finding is the same: reference `ZeroCoupled.Web.Contracts`
  (or, for `pubsub_tuple`, a typed fact routed through the manifest). Register
  next to `CorePurity`/`ComponentPurity` in `.credo.exs`; it joins the same
  `mix credo` / `mix test` seam.
  """
  use Credo.Check,
    category: :design,
    base_priority: :high,
    explanations: [
      check: """
      Cross-boundary string/atom contracts must be single-sourced in
      `ZeroCoupled.Web.Contracts` (or a typed fact), never restated as a literal
      in markup or at an effect/message call site.
      """
    ]

  alias ZeroCoupled.Credo.ComponentPurityRules, as: Rules

  @contract_rules [:event_string, :dom_contract, :contract_literal, :pubsub_tuple]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if String.starts_with?(source_file.filename, "test/") do
      # Tests are consumers of the vocabulary in assertions and must be able
      # to construct effects/messages with literal fixtures — the rule
      # governs production single-sourcing.
      []
    else
      check(source_file, params)
    end
  end

  defp check(source_file, params) do
    source = SourceFile.source(source_file)
    issue_meta = IssueMeta.for(source_file, params)

    (Rules.contract_findings(source) ++ Rules.call_site_findings(source))
    |> Enum.filter(&(&1.rule in @contract_rules))
    |> Enum.reject(&colocated_event?(&1, source))
    |> Enum.map(fn f ->
      format_issue(issue_meta,
        message: "[#{f.rule}] #{f.message}",
        line_no: f.line,
        trigger: f.trigger
      )
    end)
  end

  # An event literal whose `handle_event` clause lives in the same file is a
  # *colocated* contract — emitter and consumer share one module (S5's best
  # case, e.g. a LiveComponent's own `phx-target={@myself}` form events).
  # The rule targets scattered contracts, which are cross-file by definition.
  defp colocated_event?(%{rule: :event_string, trigger: trigger}, source),
    do: String.contains?(source, ~s[handle_event("#{trigger}"])

  defp colocated_event?(_finding, _source), do: false
end
