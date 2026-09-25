defmodule ZeroCoupled.Credo.CrossSlotRead do
  @moduledoc """
  Credo wrapper for the R2 rule (sibling to CorePurity/ComponentPurity). Scopes
  to `features/*.ex` and reports each peer-slot read. Detection lives in the
  Credo-free `CrossSlotReadRules` (so the same rule runs as a standalone
  measurement, `run_cross_slot_read.exs`). Register in `.credo.exs` once the
  surface is clean.
  """
  use Credo.Check, category: :design, base_priority: :high

  alias ZeroCoupled.Credo.CrossSlotReadRules

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if String.contains?(source_file.filename, "/features/") do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.source()
      |> CrossSlotReadRules.findings()
      |> Enum.map(fn f ->
        format_issue(issue_meta,
          message:
            "[cross_slot_read] #{f.module} (slot #{inspect(f.own_slot)}) reads peer slot " <>
              "session.#{f.slot} — resolve it in the composition and pass it in",
          line_no: f.line,
          trigger: "session.#{f.slot}"
        )
      end)
    else
      []
    end
  end
end
