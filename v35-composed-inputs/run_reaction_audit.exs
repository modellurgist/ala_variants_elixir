# Whole-program reaction-placement audit (would ship as `mix zc.audit.reactions`).
#   cd amazin-variants/v35-composed-inputs && elixir run_reaction_audit.exs
Code.require_file("lib/zero_coupled/gen/reaction_audit.ex")

{_findings, stats, shell, manifest} = ZeroCoupled.Gen.ReactionAudit.run("lib")

IO.puts("REACTION PLACEMENT AUDIT\n")

IO.puts("shell-clause reactions (#{stats.shell_total}):")
Enum.each(shell, fn r ->
  mark = if r.verdict == :ok, do: "ok   ", else: "FLAG "
  IO.puts("  #{mark} #{r.where} #{r.detail}")
end)

IO.puts("\nmanifest reactions (#{stats.manifest_total}):")
manifest
|> Enum.group_by(& &1.verdict)
|> Enum.each(fn {v, rs} ->
  mark = if v == :ok, do: "ok", else: "FLAG"
  IO.puts("  #{mark}: #{length(rs)}" <> if(v != :ok, do: " — " <> Enum.map_join(rs, "; ", & &1.where), else: ""))
end)

IO.puts("\n#{stats.findings} placement finding(s).")
if stats.findings == 0, do: IO.puts("Every reaction is on the correct side of the crossover.")
