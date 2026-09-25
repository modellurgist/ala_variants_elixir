# ala_variants_elixir

Worked Elixir/Phoenix designs that the **ALA Checklist** is applied to — the
example apps behind the blog posts. The checklist and encoding notation
themselves live in [modellurgist/ala_checklist](https://github.com/modellurgist/ala_checklist);
the Elixir linter is [modellurgist/ala_lint_elixir](https://github.com/modellurgist/ala_lint_elixir).

> Independent, unofficial examples applying John Spray's
> [Abstraction Layered Architecture](https://www.abstractionlayeredarchitecture.com/).
> Not affiliated with or endorsed by the author.

Each directory is a self-contained mix project (own `mix.exs`, config, and deps),
so there is no shared harness or switch script — `cd` into one and run it:

| Directory | Blog post | What it shows |
|---|---|---|
| `v30-committed-codegen/` | [committed codegen](https://github.com/modellurgist) | Manifest-as-data + generated, committed glue; `mix zc.gen --check` in CI |
| `v35-composed-inputs/` | composed inputs | Composed inputs on the committed-codegen spine; hoisted calibration |
| `v36-vernacular-core/` | vernacular core | A vernacular `Shop.*` core with linter-enforced purity |
| `v38-lint-guided/` | lint-guided | A monolith fork brought to ALA by following `ala_lint_elixir` |
| `coffee_maker/` | coffee-maker LiveView | The ALA coffee-maker domain (extracted, dependency-free) |

Run any variant:

```bash
cd v35-composed-inputs
mix deps.get
mix test
```

`coffee_maker/` is the domain model extracted from the study as a dependency-free
library; see its own README for the LiveView note.

## License

Licensed under the [MIT License](./LICENSE). Fork and use freely, including
commercially; keep the copyright notice.
