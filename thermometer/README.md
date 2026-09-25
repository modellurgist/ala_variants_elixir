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
| `--super-strict` | 67 — the aspirational R11 flags `push_reading`'s two nil-guards |

It is a plain source file, not a mix project — the point is to read it and lint
it, not run it.
