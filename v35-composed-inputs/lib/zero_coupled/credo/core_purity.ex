defmodule ZeroCoupled.Credo.CorePurity do
  @moduledoc """
  Custom Credo check enforcing v28's central invariant: the pure
  application core is framework-free.

  The cart aggregate, the capabilities, the effect vocabulary, the
  session wiring, and the domain abstractions may not reference
  `Phoenix.*` or the web layer (`ZeroCoupledWeb.*`). Effects are
  returned as inert data and interpreted only at the shell edge, so
  the whole core stays testable with plain ExUnit — this check keeps
  it that way. (Ecto is permitted: it is the platform, used purely for
  in-memory changeset validation, not a peer.)
  """
  use Credo.Check,
    category: :design,
    base_priority: :high,
    explanations: [
      check: """
      The application core must not depend on Phoenix or the web layer.

      Keep side effects as data (`ZeroCoupled.Effects`) and interpret
      them in the LiveView shell instead.
      """
    ]

  @core_matchers [
    "lib/zero_coupled/cart.ex",
    "lib/zero_coupled/effects.ex",
    "lib/zero_coupled/feature/",
    "lib/zero_coupled/features/",
    "lib/zero_coupled/domain/"
  ]

  @forbidden_roots [:Phoenix, :ZeroCoupledWeb]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if core_file?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp core_file?(path), do: Enum.any?(@core_matchers, &String.contains?(path, &1))

  # V29 carve-out: a feature file's `*.Components` sibling module is the
  # feature's presentational surface and legitimately uses
  # Phoenix.Component (platform coupling, not peer coupling). Prune that
  # subtree; the pure sibling modules in the same file stay checked.
  defp traverse({:defmodule, _, [{:__aliases__, _, parts} | _]} = ast, issues, _issue_meta)
       when is_list(parts) do
    if List.last(parts) == :Components do
      {{:__block__, [], []}, issues}
    else
      {ast, issues}
    end
  end

  defp traverse({:__aliases__, meta, [root | _] = parts} = ast, issues, issue_meta)
       when root in @forbidden_roots do
    {ast, [issue_for(issue_meta, meta[:line], Enum.map_join(parts, ".", &to_string/1)) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line, module) do
    format_issue(issue_meta,
      message: "Application core must not depend on the web layer/framework: #{module}",
      line_no: line
    )
  end
end
