# ala_variants_elixir

Worked Elixir/Phoenix designs that the **ALA Checklist** is applied to — the
example apps behind the blog posts. The checklist and encoding notation
themselves live in [modellurgist/ala_checklist](https://github.com/modellurgist/ala_checklist);
the Elixir linter is [modellurgist/ala_lint_elixir](https://github.com/modellurgist/ala_lint_elixir).

New to ALA? [getdown.dev](https://getdown.dev) has an introduction to it, guides to applying it,
and posts walking through most of the designs here.

> Independent, unofficial examples applying John Spray's
> [Abstraction Layered Architecture](https://www.abstractionlayeredarchitecture.com/).
> Not affiliated with or endorsed by the author.

Each `v*` directory is a self-contained mix project (own `mix.exs`, config, and
deps), so there is no shared harness or switch script — `cd` into one and run it.
`coffee_maker/` is a dependency-free mix lib, and `thermometer/` holds one folder per step of
Spray's thermometer example, each runnable with `elixir`:

| Directory | Blog post | What it shows |
|---|---|---|
| `v30-committed-codegen/` | [composed inputs](https://getdown.dev/blog/intro-to-v35-composed-inputs/) (its spine, now covered there) | Manifest-as-data + generated, committed glue; `mix zc.gen --check` in CI |
| `v35-composed-inputs/` | [composed inputs](https://getdown.dev/blog/intro-to-v35-composed-inputs/) | Composed inputs on the committed-codegen spine; hoisted calibration |
| `v36-vernacular-core/` | [vernacular core](https://getdown.dev/blog/intro-to-v36-vernacular-core/) | A vernacular `Shop.*` core with linter-enforced purity |
| `v38-lint-guided/` | [lint-guided](https://getdown.dev/blog/intro-to-v38-lint-guided/) | A monolith fork brought to ALA by following `ala_lint_elixir` |
| `v39-bound-ports/` | [bound ports](https://getdown.dev/blog/intro-to-v39-bound-ports/) | Features as `{state, outputs}` functions; each page is one `bindings/1` map from feature ports to streams, assigns, flashes, timers, other features; a 111-line Binder runs it |
| `v40-circuit-instances/` | [circuit instances](https://getdown.dev/blog/intro-to-v40-circuit-instances/) | The same features as Step instances in a circuit the page wires at mount; LiveComponents own their events and push into named inputs; loading is a store source |
| `v41-feature-components/` | [feature components](https://getdown.dev/blog/intro-to-v41-feature-components/) | The `phx.gen.live` shape: each feature a LiveComponent instance owning its state, stream, events and store writes; the page places, configures, and routes announcements with `send_update`; 18 lines of paradigm |
| `v41-max/` | [V41-max](https://getdown.dev/blog/intro-to-v41-max/) | V41 taken to 100 on the full checklist: panels plus one route table per page; every word from the page; one hop per cross-feature effect |
| `v39-max/` | [V39-max](https://getdown.dev/blog/intro-to-v39-max/) | V39 taken to 100: no page helpers, configured domain instances behind a `Call` port, a test that every port is bound or grounded; zero hops |
| `v38-max/` | [V38-max](https://getdown.dev/blog/intro-to-v38-max/) | V38 taken to 100: one plain LiveView whose `land/3` clauses are the wiring, one per port; zero hops |
| `coffee_maker/` | [coffee-maker LiveView](https://getdown.dev/blog/coffee-maker-liveview/) | The ALA coffee-maker domain (extracted, dependency-free) |
| `thermometer/` | [intro thermometer](https://getdown.dev/blog/intro-to-ala-thermometer/); [the thermometer grows up](https://getdown.dev/blog/thermometer-grows-up/) | Spray's thermometer step by step (§1.6.1 to §1.6.6), one folder per step, each runnable and scored by `ala_lint` |

Run any variant:

```bash
cd v39-bound-ports
mix deps.get
mix test
```

`coffee_maker/` is the domain model extracted from the study as a dependency-free
library; see its own README for the LiveView note.

## License

Licensed under the [MIT License](./LICENSE). Fork and use freely, including
commercially; keep the copyright notice.
