# thermometer

John Spray's thermometer example, taken step by step through his book (the section numbers are
from [his site](https://www.abstractionlayeredarchitecture.com/)), in Elixir. Each folder is one
step. It holds `.ex` source (so `ala_lint` can score it) and a `run.exs` you can run with `elixir`.
The code is the code in the blog posts:
[a first look at ALA, through a thermometer](https://getdown.dev/blog/intro-to-ala-thermometer/)
covers 1.6.1 and 1.6.3, and [the thermometer grows up](https://getdown.dev/blog/thermometer-grows-up/)
covers 1.6.4 to 1.6.6.

| Folder | Spray | What changes | `ala_lint` default / strict / super-strict |
|---|---|---|---|
| `1.6.1-bad/` | §1.6.1 | Procedures calling each other as peers, literals baked in, hidden state in the process dictionary | 0/F · 0/F · 0/F |
| `1.6.3-composed/` | §1.6.3 | Generic domain abstractions under a `Thermometer` composition that holds the literals. The composition still handles every value, carries each updated struct, and guards with `if`s | 100/A · 100/A · 67/C |
| `1.6.4-chain/` | §1.6.4 | Build, then run: the app lists configured instances, and `Chain` moves the data. `:quiet` replaces the `if`s | 100/A · 100/A · 100/A |
| `1.6.4-stream/` | §1.6.4 | The same goal with streams: each abstraction is a configured `Stream -> Stream` function | 100/A · 100/A · 100/A |
| `1.6.5-circuit/` | §1.6.5 | Instances wired as a graph, with no processes; the sampler fans out to a display and a high-temperature tracker | 100/A · 100/A · 100/A |
| `1.6.5-processes/` | §1.6.5 | One process per instance with a wired output port; the literal translation, for concepts that really are concurrent | 100/A · 100/A · 100/A |
| `1.6.6-liveview/` | §1.6.6 | LiveView: HEEx nesting as the "display inside" wiring, assigns as where the dataflow lands, and a runner that pushes results into them | 100/A · 100/A · 100/A |
| `shared/` | | The dataflow paradigm (`Step`, `Chain`), the graph runner (`Circuit`), and the generic domain abstractions the later steps share | |

```bash
cd 1.6.4-chain && elixir run.exs      # every step's run.exs works the same way
cd 1.6.6-liveview && elixir run.exs   # fetches phoenix_live_view via Mix.install, then renders
```

From 1.6.3 on, every step prints the same three readings (40.3, 40.6, 40.5) for the same 30
simulated inputs. 1.6.1 uses Spray's own literals, so its numbers differ.

## About the scores

`score.exs` produces them. Run it from an `ala_lint_elixir` checkout with
`mix run ../ala_variants_elixir/thermometer/score.exs`. It declares a layer map per step:
- application;
- domain;
- where present, the paradigm layer (`Chain`, `Circuit`, `Stage`);
- the `Step` port protocol below the paradigm layer;
- a LiveView paradigm layer (`CircuitRunner`, `ToAssign`) above it.

What the scores do and don't show:

- **1.6.1** fails on R4 (the process dictionary) and on R11 (branching and arithmetic in the
  application). The linter misses the scattered literals and the chain of product functions calling
  each other, because the whole bad version is one module, which it treats as one application
  abstraction. The checklist's R1 "working chain" and R3 catch those; the linter can't yet.
- **1.6.3** is clean at the default and strict levels. Its remaining findings are R11's: the two
  nil-guard `if`s in `push_reading/2`, reported as guards, and the application's share of the
  functions. They're real findings, scored only under `--super-strict`.
- **1.6.4 onward** is clean at every level. The step the linter *can't* see is the most important
  one: from 1.6.4 the application no longer handles the data. Measuring that is still open (see the
  ALA Checklist, "Past the pipe").
