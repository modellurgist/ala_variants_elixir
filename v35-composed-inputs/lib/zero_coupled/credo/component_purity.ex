defmodule ZeroCoupled.Credo.ComponentPurity do
  @moduledoc """
  V32 custom Credo check: the LiveView **presentation layer** must depend only
  on paradigm-typed ports, never on the domain, its peers, or raw string
  contracts. Sibling to `ZeroCoupled.Credo.CorePurity` — same shape, inverted
  target (core-must-not-touch-web → presentation-must-not-touch-domain).

  The detection lives in `ZeroCoupled.Credo.ComponentPurityRules` (Credo-free,
  so the same rules also run as a standalone measurement instrument). This
  module is the thin Credo adapter: it scopes to presentation files and maps
  each rule finding to a Credo issue.

  Register for local + CI runs exactly like `CorePurity` (in `.credo.exs`):

      requires: ["lib/zero_coupled/credo/core_purity.ex",
                 "lib/zero_coupled/credo/component_purity_rules.ex",
                 "lib/zero_coupled/credo/component_purity.ex"],
      checks: %{extra: [
        {ZeroCoupled.Credo.CorePurity, []},
        {ZeroCoupled.Credo.ComponentPurity, []}
      ]}

  `mix credo` already runs in `:dev`/`:test`, and `mix test` runs the same seam
  as `zc.gen --check`, so this fails the build on drift with no new tooling.
  """
  use Credo.Check,
    category: :design,
    base_priority: :high,
    explanations: [
      check: """
      A presentation module (LiveView, ActionView, or a feature's `*.Components`)
      must not reference the domain, reach into nested domain shape, or hardcode
      intent/hook/stream string contracts.

      Take a projected port value instead of a domain struct; pass events as
      ports (interpolated bindings, not literal `phx-click="…"`); and source
      hook names and stream ids from a single contracts module.
      """
    ]

  alias ZeroCoupled.Credo.ComponentPurityRules

  # A file is presentation if it is a pure *renderer* — an ActionView
  # (`*_view.ex`), a feature's `*.Components` module, a Catalog UI abstraction,
  # or the shared component library. Deliberately NOT presentation:
  #
  #   * `pages/*/manifest.ex` + `generated.ex` + the page shell — the wiring
  #     layer, whose whole job is naming features (migration finding: the
  #     spike's `/pages/` marker misclassified these and produced ~200 false
  #     findings on `__manifest__` alone);
  #   * LiveView shells (`live/*/index.ex` etc.) — mount/handle_event do I/O
  #     and wiring by design; their inline markup stays governed by
  #     ContractPurity's app-wide `~H` scan.
  @presentation_path_markers ["/catalog/", "/components/"]

  # This check owns the **coupling axis** only: `domain_ref` (AST) and
  # `domain_shape` (markup, advisory). The string-contract rules
  # (`event_string`, `dom_contract`, …) belong to the app-wide ContractPurity —
  # with both registered, keeping them here double-reported every renderer
  # finding (a migration refinement over the spike, which predated
  # ContractPurity).
  @impl true
  def run(%SourceFile{} = source_file, params) do
    source = SourceFile.source(source_file)

    if presentation?(source_file.filename, source) do
      issue_meta = IssueMeta.for(source_file, params)
      scope = if whole_file_renderer?(source_file.filename), do: :all, else: :components_only

      domain = ComponentPurityRules.domain_findings(source, scope)
      shape = source |> ComponentPurityRules.contract_findings() |> Enum.filter(&(&1.rule == :domain_shape))

      Enum.map(domain ++ shape, fn f ->
        format_issue(issue_meta,
          message: "[#{f.rule}] #{f.message}",
          line_no: f.line,
          trigger: f.trigger
        )
      end)
    else
      []
    end
  end

  # A feature file mixes pure siblings (CorePurity's territory) with its
  # Components module; only the latter is scanned for domain refs.
  defp whole_file_renderer?(path) do
    Enum.any?(@presentation_path_markers, &String.contains?(path, &1)) or
      String.ends_with?(path, "_view.ex")
  end

  defp presentation?(path, source) do
    Enum.any?(@presentation_path_markers, &String.contains?(path, &1)) or
      String.ends_with?(path, "_view.ex") or
      String.contains?(source, ".Components do")
  end
end
