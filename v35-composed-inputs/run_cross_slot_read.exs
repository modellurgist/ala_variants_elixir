# R2 measurement: report every peer-slot read in the feature Intents modules.
#   cd amazin-variants/v35-composed-inputs && elixir run_cross_slot_read.exs
Code.require_file("lib/zero_coupled/credo/cross_slot_read_rules.ex")

alias ZeroCoupled.Credo.CrossSlotReadRules

files = Path.wildcard("lib/zero_coupled/features/*.ex")

findings =
  for f <- files, finding <- CrossSlotReadRules.findings(File.read!(f)), do: {f, finding}

IO.puts("cross-slot reads in feature intents: #{length(findings)}\n")

findings
|> Enum.group_by(fn {f, _} -> Path.basename(f) end)
|> Enum.each(fn {file, fs} ->
  IO.puts("  #{file}")

  Enum.each(fs, fn {_, %{own_slot: own, slot: slot, line: line}} ->
    IO.puts("    L#{line}: slot #{inspect(own)} reads session.#{slot}")
  end)
end)
