# thermometer

The ALA thermometer from the [intro blog post](https://github.com/modellurgist),
in a single file. It is the smallest worked example: four generic domain
abstractions (`OffsetAndScale`, `LowPassFilter`, `SampleEvery`, `Display`) under
a `Thermometer` composition that does the wiring and holds the application
literals.

Linting it with `ala_lint_elixir` and a layer map (Thermometer at the top, the
rest below) reproduces the score the blog reports:

| Tier | Score |
|---|---|
| default (`mix ala.lint`) | **100 / 100** |
| `--strict` | **100 / 100** |
| `--super-strict` | 67: R11 flags `push_reading`'s two nil-guard `if`s |

The R11 flag is a real finding, not noise. By Spray's standard the application
layer holds no `if`s, and he flags the same guard in his own version (his site,
§1.6.3). `grows_up/` below moves the guards into the connection mechanism.

It is a plain source file, not a mix project — the point is to read it and lint
it, not run it.

## `grows_up/`: Spray's next steps

`thermometer.ex` is the first rung of Spray's ladder (his §1.6.3): the
composition is right, but `push_reading` still handles every value and the
filter's state, and branches on the sampler. `grows_up/` holds the code from the
follow-up post, taking the same domain abstractions up the next rungs. These
are some Elixir ways to meet each goal, not the only ones.

| File | Spray | What it shows |
|---|---|---|
| `dataflow.exs` | | shared: the `Step` protocol and `Chain` (the dataflow paradigm), plus the generic domain abstractions |
| `chain.exs` | §1.6.4 | build, then run: the app lists configured instances, `Chain` moves the data; `:quiet` replaces the nil-guard `if`s |
| `stream.exs` | §1.6.4 | the monad reading: each abstraction is a configured `Stream -> Stream` function, then `Stream.run/1` |
| `circuit.exs` | §1.6.5 | a pure graph of named instances plus a runner, so one output can feed two inputs |
| `stage.exs` | §1.6.5 | one process per instance with a wired output port; the literal translation, for concepts that really are concurrent |
| `live.exs` | §1.6.6 | LiveView: HEEx nesting as the "display inside" wiring, assigns as where the dataflow lands, and a runner that pushes results into them |

Each is a script:

```bash
cd grows_up
elixir chain.exs     # also stream.exs, stage.exs
elixir live.exs      # fetches phoenix_live_view via Mix.install, then renders the page
```

The dataflow scripts print the same three readings for the same simulated
input, and `live.exs` renders the same value (with a high of 40.6).
