# V36 — Vernacular Core

The variant designed in [`ala_lab/docs/Q-familiar-ala-variant.md`](../../ala_lab/docs/Q-familiar-ala-variant.md),
built for real: **the most ALA structure you can get while staying ordinary Phoenix/Elixir** — no
macros, no codegen, no manifest, no facts/reactions vocabulary, no custom checkers. The bet is that
ALA's *structure* (knowledge flows down, private state per feature, wiring in one place, config on
the diagram) is separable from ALA's *machinery* (the things that cost familiarity), and that a
developer greps this after one example.

**12 tests, 0 failures; compiles clean under `--warnings-as-errors`.** Dependency-free (integer
cents, no Money/Phoenix) so the core is testable without a framework.

## Shape

```
lib/shop/            the functional core — plain modules, each a private struct + pure functions
  cart.ex            Cart      (items, pricing; returns {state, [outcome]} or {state, value, outcomes})
  wishlist.ex        Wishlist
  undo.ex            Undo
  checkout.ex        Checkout  (a pure step machine)
  pricing.ex         Pricing   — generic domain calcs; calibration passed in as data
  outcome.ex         Outcome   — the effect vocabulary (typed constructors; a typo is a compile error)
lib/shop_web/
  cart_page.ex       CartPage  — THE COMPOSITION: a struct with one slot per feature + one handle/3
                                 clause per action; cross-feature wiring is explicit calls, here
  cart_shell.ex      CartShell — the thin shell: run the composition, interpret outcomes at the edge
```

A real Phoenix LiveView is a 3-line delegation to the shell (shown in `cart_shell.ex`'s docs); the
shell is kept dependency-free here so the whole variant compiles and tests offline.

## What makes it familiar (target: 5)

Everything is something a Phoenix dev has already written: context-style modules with structs and
pure functions, a `handle/3` reducer, `apply_outcome/2`, a thin shell. **Nothing to `use`, no
generated file, no `mix` task, no manifest DSL, no Credo plugin.** One worked example
(`Wishlist.toggle/2` + the `:remove_item` clause showing cart→undo wiring) teaches the whole thing.

## What makes it ALA (the structure, by discipline not machinery)

- **Zero-coupling** — features never call peers; only the composition calls features, and cross-
  feature consequences are returned as data (a removed item, outcomes) for `CartPage.handle` to wire.
- **State independence** — one private struct per feature; only its own module writes it.
- **Requirements-locus** — calibration (`@pricing`: shipping rates, promo table, gift-wrap, tiers)
  lives in the composition and is injected into the generic `Pricing`; the domain stays product-free.
- **State as a wire** — the whole page is threaded `{page, outcomes}`; no process state.

## ala_lint score (measured, AlaLint 0.1.0)

Run: `mix ala.lint` in a project that deps `ala_lint`, or from the ala_lint repo:
`AlaLint.analyze(".../v36-vernacular-core/lib", config_modules: ["ShopWeb.CartPage"])`.

| | severity | breadth (functions-with-a-violation) |
|---|---|---|
| default | 84 / B | 94 / A |
| config-locus-aware (`CartPage` = config module) | **92 / A** | **94 / A** |

Clean on **R1 (no cycles → zero-coupling), R2, R4, R5, R7.** For comparison, v30 = 78, v35 = 80
(severity). So V36 — with none of the frontier's machinery — matches or beats them on the R1–R7
structural rubric, which is the design's core claim.

Remaining findings, honestly:

- **R3 ×2** — the `window_ms: 5_000` default baked in `Undo.new/1` (a real minor leak; the
  composition also passes it, so the default could be dropped). With `CartPage` marked as the
  config locus, the `@pricing` literals are correctly *not* flagged (they're on the diagram, where
  R3 wants them).
- **R6 ×3** — `Cart.empty?/1`, `Undo.pending?/1`, `Pricing.gift_wrap/2` flagged as "wraps a
  primitive." Two are meaningful named predicates (`empty?`, `pending?`) — idiomatic Elixir, and a
  case where R6's heuristic over-flags a legitimate query. `gift_wrap/2` is a genuinely thin wrapper.

## The honest ceiling (what it gives up vs V30/V35)

`ala_lint` measures *structure* (R1–R7), and V36 scores at the top of it — but the frontier
variants bought two things V36 trades away for familiarity, neither visible to the rubric:

1. **Enforcement.** V36's zero-coupling/R3/R5 hold *by discipline*, not by `CorePurity`/
   `ContractPurity`/`--check`. The recommended top-up (no familiarity cost): add `ala_lint` to CI
   with `mix ala.lint --min-score N` — the code stays vernacular, regressions fail the build.
2. **Declarative append-only wiring.** Adding a cross-feature interaction *edits* `CartPage.handle`
   (a few obvious lines) rather than *appending* a manifest row — OCP ~4 vs 5, and no facts/
   reactions layer (lower S1–S5).

So V36 is not "more ALA than V30/V35"; it is **as structurally ALA on R1–R7 while staying
familiarity-5**, which none of the frontier variants do. Whether "vernacular + discipline + CI
lint" *feels* like a 5 to a fresh developer is the open empirical question (the add-a-feature eval
in [`ala_lab/docs/Q-next-directions.md`](../../ala_lab/docs/Q-next-directions.md)).

## Verify

```
mix test                       # 12 tests, 0 failures
# from the ala_lint repo:
mix run --no-start -e 'AlaLint.analyze("<this>/lib", config_modules: ["ShopWeb.CartPage"]) |> AlaLint.Report.to_text() |> IO.puts()'
```
