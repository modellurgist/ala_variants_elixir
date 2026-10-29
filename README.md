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
| `v38-max/` | [V38-max](https://getdown.dev/blog/intro-to-v38-max/) | V38 taken to 100: one plain LiveView whose `wire/3` clauses are the wiring, one per port; zero hops |
| `v45-checked-clauses/` | [checked clauses](https://getdown.dev/blog/intro-to-v45-checked-clauses/) | 100 on the full checklist with zero hops: V38-max's `wire/3` clauses with named instances, a one-line coverage test, and an optional compile-time wiring check |
| `v50-plain-liveview/` | [plain LiveView](https://getdown.dev/blog/intro-to-v50-plain-liveview/) | V48 at familiarity 5: plain LiveView, no LiveComponents, every update inside one `handle_event`; full checklist 100 by hand, `ala_lint` 100 at every tier; every hop traced under the suite, which fails on an output never routed |
| `v51-plain-stories/` | [plain stories](https://getdown.dev/blog/intro-to-v51-plain-stories/) | V50 with Spray's Features layer: user-story modules (`EditCart`, `UndoRemoval` shared by the cart and the portal, …) over smaller state abstractions; first variant to meet 10 of 10 checked rules under `--super-strict`; every hop traced under the suite, which fails on an output never routed |
| `v51b-shared-story/` | [shared editing story](https://getdown.dev/blog/intro-to-v51b-shared-story/) | V51 with one `EditLines` story edited by both the cart and the order, each page handing in its row component and its own pricing story (`PriceCart`, `PriceOrder`); pages may ground outputs of a shared story; the running trace was first built here and now lives in V50 and V51 too; `lint.exs` holds the layer map (100 at every tier) |
| `v52-ala-light/` | — | V51B under ALA Light (subset 2 of `ala_lab/docs/Q-ala-light-subsets.md`): R11 read as advice, not scored; the three one-page rules (volume tier, gift-wrap cost, promo validation) folded back into their pages as pure functions handed to the same parts; otherwise V51B's code, so the difference shows during changes; 100 at every tier with R11 advisory |
| `v53-ala-variation-ports/` | — | V52 under subset 3 of `ala_lab/docs/Q-ala-light-subsets.md`: ports only at variation points (a part placed by two compositions today, or a paradigm). `EditLines`, `UndoRemoval`, `ChangeFeed` and `RecordEdit` stay wired; the seven stories placed by one page fold into it, and the pages call their state parts and use what they answer; 150 tests; 100 at every tier with R11 advisory (25 R11 findings, one scored `clone` that rounds away) |
| `v54-layered-v0/` | — | V0 (conventional Phoenix) under ALA form 1: dependencies point down four layers (app, contexts, domain, platform) with no context calling another, every §7 value in one app-layer `Calibration` module passed down, and pricing, shipping, volume tier, promo code and stock status as named pure domain rules; no ports, wiring or stories, and the LiveViews stay V0's; 155 tests; 100 at every tier with the port and composition checks off |
| `v55-layered-v0-stable/` | — | V54 under ALA form 1b: form 1's four rules plus three about interfaces. Each channel's calibration is one `%Channel{}` and a page's session values one `%Shop{}`, which every session-scoped context function takes first (largest context arity 5 to 3); rules take the channel and a value and are extended, not reshaped; tests sit at the pages and contexts, with rule unit tests only for boundaries; 146 tests; 100 at every tier with V54's checks |
| `v56-layered-v0-honest/` | — | V55 under ALA form 1c: form 1b's seven rules plus two corrections. A value the domain needs is an enforced struct key, not a default (`%Channel{}` enforces seven of its nine fields, `%Shop{}` its `cart_id`), and a guard is checked by the context function that writes the data (promo code and shipping method writable only through their checks; orders refuse a missing address or another cart's items); 149 tests; 100 at every tier with V55's checks |
| `v57-layered-v0-feed/` | — | V56 under ALA form 2: form 1c's nine rules plus a live-update paradigm. A change made elsewhere reaches an open page only through `GoodDeal.ChangeFeed`, which publishes facts keyed by identity (`:product_added`, `:details`, `:price`, `:stock`, `:product_removed`, each with only the changed values) on one topic per kind; a page subscribes once with a map of kinds to functions. Replaces `ProductEvents`' whole-struct broadcasts on all four live paths; 156 tests; 100 at every tier with V56's checks |
| `v58-layered-v0-roots/` | — | V56 under ALA hybrid 1 (form 1c + 3): form 1c's nine rules plus two. Each page builds the parts it uses (its `%Shop{}`, the pricing configured for its channel, `%UndoRemoval{}` with its stream and window, checkout's success URL) in one private `parts/…` called from `mount` and assigned once; handlers read `parts.*` and nothing is wired (V56's `on_mount` shop hook is gone). Tests build `%Channel{}`, `%Shop{}` and shipping methods only through production's builders (`Calibration.channel/2` takes overrides; the literal channel fixture is gone); 151 tests; 100 at every tier with V56's checks |
| `v59-light-ala/` | — | **The recommended light ALA.** V58 under form 1c with composition roots and two guards. Every builder of a config or context struct takes its required values plus keyword overrides (`CartSession.shop(channel, cart_id: …)`, `Calibration.pricing/3`), so a new field never changes an arity; tests build only through them. A write to a session cart sees a current cart: each root's `mount` attaches `CartSession.guard_open_cart/4`, which reloads the page through the session plug when its cart has closed, and every `ShoppingCart` writer (and both `Orders` submits) refuses a closed cart with `{:error, :cart_closed}`. V58's last R7 clone is gone: repricing moved into `UndoRemoval` and the cart and portal roots compose `CartSession.editor_parts/4`. README states the twelve rules; 175 tests; 100 at every tier with V58's checks, R7 met under strict |
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
