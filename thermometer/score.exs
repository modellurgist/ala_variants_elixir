# Scores every step with ala_lint, using the layer map each step declares below.
# Run from an ala_lint_elixir checkout:  mix run ../ala_variants_elixir/thermometer/score.exs
base = __DIR__
shared = Path.join(base, "shared")
dom = ~w(OffsetAndScale LowPassFilter SampleEvery NumberToString Display Maximum)
exact = fn names -> Enum.map(names, &Regex.compile!("^#{&1}$")) end
steps = [
  {"1.6.1-bad", ["1.6.1-bad"], [{:app, exact.(~w(BadThermometer))}]},
  {"1.6.3-composed", ["1.6.3-composed"], [{:app, exact.(~w(Thermometer))}, {:domain, exact.(dom)}]},
  {"1.6.4-chain", ["1.6.4-chain", :shared], [{:app, exact.(~w(Thermometer))}, {:domain, exact.(dom)}, {:paradigms, exact.(~w(Chain Circuit))}, {:ports, exact.(~w(Step))}]},
  {"1.6.4-stream", ["1.6.4-stream"], [{:app, exact.(~w(Thermometer))}, {:domain, exact.(dom)}]},
  {"1.6.5-circuit", ["1.6.5-circuit", :shared], [{:app, exact.(~w(Thermometer))}, {:domain, exact.(dom)}, {:paradigms, exact.(~w(Chain Circuit))}, {:ports, exact.(~w(Step))}]},
  {"1.6.5-processes", ["1.6.5-processes", :shared], [{:app, exact.(~w(Thermometer))}, {:domain, exact.(dom)}, {:paradigms, exact.(~w(Chain Circuit Stage))}, {:ports, exact.(~w(Step))}]},
  {"1.6.6-liveview", ["1.6.6-liveview", :shared], [{:app, exact.(~w(Thermometer ThermometerLive))}, {:domain, exact.(dom ++ ~w(Widgets))}, {:liveview_paradigm, exact.(~w(CircuitRunner ToAssign))}, {:paradigms, exact.(~w(Chain Circuit))}, {:ports, exact.(~w(Step))}]}
]
for {name, dirs, layers} <- steps do
  roots = Enum.map(dirs, fn :shared -> shared; d -> Path.join(base, d) end)
  n = AlaLint.analyze(roots, layers: layers)
  st = AlaLint.analyze(roots, layers: layers, strict: true)
  su = AlaLint.analyze(roots, layers: layers, super_strict: true)
  IO.puts("#{String.pad_trailing(name, 16)} default #{n.score}/#{n.grade}  strict #{st.score}/#{st.grade}  super #{su.score}/#{su.grade}  funcs #{n.functions}  cover #{n.layer_coverage && n.layer_coverage.pct}%")
  for f <- su.findings, do: IO.puts("    #{f.rule} #{f.module}: #{f.message}")
end
