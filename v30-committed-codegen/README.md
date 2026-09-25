# V30 — Committed Codegen

The 30th design variant in the zero-coupled Phoenix LiveView exploration: **V29.1 with its
manifest glue turned into committed source**. V29.1's three open scorecard cells — familiarity 3,
trace locality 4, cognitive load 4 — were one problem: the composition's glue expanded invisibly
inside the compiler (`@before_compile`). V30 makes one move: the glue becomes an ordinary `.ex`
file in the repo, written by `mix zc.gen`. Read it, grep it, breakpoint it, review it in diffs.

Implemented per [`ala_lab/docs/v30-committed-codegen.md`](../../ala_lab/docs/v30-committed-codegen.md);
direction chosen in [`ala_lab/docs/Q-v30-direction-analysis.md`](../../ala_lab/docs/Q-v30-direction-analysis.md).

**Building on V30:** [`docs/techniques.md`](docs/techniques.md) (one worked recipe per mechanism),
[`docs/adding-a-feature.md`](docs/adding-a-feature.md) (end-to-end walkthrough),
[`docs/architecture.md`](docs/architecture.md) (layer map). Where V30 stands on the ALA
function-encoding rubric (R1–R5 = 17/25; R1/R4-clean, R3/R5-weak) and how the later variants climb
it: [`ala_lab/docs/ALA-encoding-applied-to-v30.md`](../../ala_lab/docs/ALA-encoding-applied-to-v30.md).

The governing rule is unchanged from V29 and now trivially true:

> **Anything generated must be exactly the code you would have written by hand — because it *is*
> committed code, reviewed like any other file.** `mix zc.gen --check` fails the build if the
> committed file ever drifts from its manifest.

This is the most Spray-literal move in the variant line (see `ala-full-summary.md` §2.5.1): *the
diagram is the source; change the diagram first; generate the wiring; the generated code need only
be readable enough to check it against the diagram.* `mix zc.gen --check` mechanizes exactly that.

**Zero web-layer macros.** V29's three-macro budget drops to **one** — only
`use ZeroCoupled.Feature.Intents` (intent metadata, in the core) remains. The
`feature`/`react`/`action_view` macros and `@before_compile` are gone.

## The shape

```
lib/zero_coupled_web/pages/cart_page/
  manifest.ex     ← THE DIAGRAM: a plain data module (no macros, no `use`). Change this first.
  generated.ex    ← COMMITTED glue (mix zc.gen). Header: "GENERATED FILE — do not edit."
lib/zero_coupled_web/pages/cart_page.ex
                  ← the hand-written LiveView: mount, irregular clauses, thin delegation, run/2
lib/zero_coupled_web/page_check.ex
                  ← runtime verify/1 + cast_params/2 (was on the deleted Page macro)
lib/zero_coupled/gen/page_generator.ex
                  ← the generator: V29's quoting helpers, retargeted to write a file
lib/mix/tasks/zc.gen.ex · zc.trace.ex
lib/zero_coupled/feature/intents.ex   ← the one remaining macro (intent metadata)
lib/zero_coupled/features/*.ex        ← ONE FILE PER FEATURE, unchanged from V29.1 (incl. Facts)
lib/zero_coupled_web/effect_interpreter.ex · effects.ex · domain/ · foundation/  ← unchanged
```

Deleted relative to V29.1: `zero_coupled_web/page.ex` (the `use ZeroCoupledWeb.Page` macro and
`@before_compile`) and `mix zc.page.dump` — subsumed, because the committed file *is* the dump.

## The manifest (a plain data module — read this file first)

```elixir
defmodule ZeroCoupledWeb.CartPage.Manifest do
  alias ZeroCoupled.Features.{CartItems, Undo, SavedItems, Wishlist, CheckoutFlow, PageUI}
  alias ZeroCoupled.Features.CartItems.Facts, as: CartFacts
  # …

  def features do
    [cart: {CartItems, render: :render_data}, undo: Undo, saved: SavedItems,
     wishlist: Wishlist, checkout: CheckoutFlow, ui: PageUI]
  end

  def reactions do
    [
      {CartFacts.ItemRemoved, to: {:undo, Undo.Intents, :capture_removed}},
      {UndoFacts.ItemRestored, to: {:cart, CartItems.Intents, :receive_item}},
      # emitter vocabulary (saved_item) → reactor port (%{item: _}) — reaction reuse:
      {SavedFacts.MovedToCart,
       to: {:cart, CartItems.Intents, :receive_item, transform: &%{item: &1.saved_item}}},
      {CartFacts.ItemSaved, to: {:saved, SavedItems.Intents, :stash}},
      # …
    ]
  end

  def action_views, do: [index: IndexView, checkout: CheckoutView]
end
```

**No `use`, no macros** — any Elixir developer reads it on sight. It compiles as ordinary code, so
a typo'd fact alias or feature module is still a plain **compile error** (V29.1's guarantee, kept
without a macro). Intents are *not* listed here; they stay declared next to their functions in each
feature's `Intents` module (`intent :remove_item, params: [item_id: :int]`).

## The generated file (committed, reviewed, greppable)

`mix zc.gen` reads the manifest and writes `pages/cart_page/generated.ex` — a `Session` struct, the
pure runners, one struct-matched `apply_fact/2` clause per react entry, one `page_event/4` clause
per declared intent (param casts inline), render dispatch, and per-slot assigns. For example:

```elixir
def apply_fact(session, %ZeroCoupled.Features.SavedItems.Facts.MovedToCart{} = fact) do
  effects = []
  payload = (&%{item: &1.saved_item}).(fact)     # ← the manifest's transform, spliced verbatim
  {new_slot, more} =
    ZeroCoupled.Features.CartItems.Intents.receive_item(Map.fetch!(session, :cart), payload)
  session = Map.replace!(session, :cart, new_slot)
  effects = effects ++ more
  {session, effects}
end
```

The generator resolves modules by **runtime introspection** (`Manifest.features/0`,
`action_views/0`, each feature's `__intents__/0` — compiler-resolved aliases) and reads only the
one thing runtime data cannot carry — the source of a `transform:` capture — from the manifest
**file's AST**, splicing it into the clause exactly as V29's macro did. Output is piped through
`Code.format_string!/1`, so diffs are minimal and generation is byte-deterministic (which is what
lets `--check` compare).

## The tooling

```bash
mix zc.gen                       # regenerate generated.ex from the manifest
mix zc.gen --check               # fail if the committed file is stale (wired into `mix test`)
mix zc.trace remove_item         # the intent's owner + params + the page's fact→reaction wiring
```

`mix zc.gen --check` is the first step of the `test` alias, so a forgotten regeneration cannot pass
CI. `mix zc.trace` answers trace-locality: it prints an intent's owning feature, its param spec,
and the full reaction table on one screen, all from committed `__manifest__/0` data.

## Ownership rules (what makes this zero-coupled) — unchanged from V29.1

- An `Intents` module may **read** any slot but **write only its own** (`put_slot/2`;
  `Map.replace!` raises on a wrong slot). Cross-slot writes happen only via **facts**.
- **Facts are typed structs owned by their emitter** (a `Facts` sibling, `@enforce_keys`) — a
  wrong/missing field or a typo'd fact alias in the manifest is a **compile error**.
- **Reactions are slot-scoped** — `(slot_state, payload) -> {slot_state, effects}` — and **never
  receive the emitter's struct**: the generated clause passes `Map.from_struct(fact)` or the
  `transform:` result, so reactors never alias an emitter.
- **One owner per intent** (duplicate → generation-time error); undeclared facts and unknown
  events **raise loudly**.
- **Per-slot assigns + render_data gating**: `put_session` assigns each slot as `@cart_slot`,
  `@wishlist_slot`, …; ActionViews read only slot assigns. Untouched slots are the same heap term
  (structural sharing), so `assign/3` no-ops and LiveView skips those features' template regions.
  The one derived assign, `@cart = CartItems.render_data(session.cart)`, is **gated**: it is
  recomputed only when the cart slot's term actually changed (O(1) `:erts_debug.same/2` check), so
  a non-cart event does zero cart-presentation work. Near-per-feature render isolation with plain
  function components — no LiveComponents — proved by two `:erts_debug.same/2` tests. This is what
  puts V30 at **R1 = 5** on the scorecard.
- `CorePurity` (Credo) proves the core Phoenix-free, carving out only each feature's `*.Components`.

## What V30 changes vs V29.1 (the scorecard cells it targets)

| Cell | V29.1 | V30 (projected) | How |
|---|---|---|---|
| Familiarity | 3 | **4** | "config module + code generator, like `phx.gen`" — a known story; zero web-layer macros |
| Trace locality | 4 | **5** | the full story is committed source (grep, breakpoint, PR review) + `mix zc.trace` on one screen |
| Cognitive load | 4 | **4–5** | nothing expands invisibly; the one new thing is regeneration discipline, held by `--check` |
| Runtime efficiency (R1) | 4 | **5** | per-slot assigns **plus** render_data gating — `@cart` recomputes only when the cart slot's term changed (O(1) identity check) |

**Projected total: 88–89** (conservative floor 88) vs V29.1's 86 — see the scorecard's V30 section.
Honest new costs: regeneration drift (mitigated to CI-failure by `--check`), generated-file merge
noise, and generator maintenance (≈ the macro maintenance it replaces).

## Testing (136 tests, 0 failures)

```
test/zero_coupled/features/*_test.exs            # pure feature tests (async, no DB)
test/zero_coupled/gen/page_generator_test.exs    # ★ NEW: the generator unit-tested in isolation
                                                 #   against a minimal fixture manifest — the win
                                                 #   committed codegen has over @before_compile
test/zero_coupled_web/pages/cart_page_test.exs   # the composed page, PURE: run_intent/run_pure;
                                                 #   verifies the manifest (PageCheck.verify/1),
                                                 #   raise paths, cast_params, per-slot sharing,
                                                 #   the render_data gate (R1=5), and that
                                                 #   generated.ex matches a fresh gen
test/zero_coupled_web/live/cart_views_test.exs   # ActionViews via render_component/2
test/zero_coupled_web/live/cart_live_test.exs    # end-to-end through the generated glue
```

The `__generated__`-string snapshot of V29 is replaced by something stronger: the whole committed
file is the snapshot (`zc.gen --check` in the test alias), and the generator itself is now a plain
function with a unit test.

```bash
cd amazin-variants/v30-committed-codegen
mix setup && mix test          # 135 tests (runs `zc.gen --check` first)
mix credo                      # includes CorePurity
mix zc.gen --check             # verify the committed glue is fresh
mix zc.trace remove_item       # read the composition's story on one screen
mix phx.server                 # http://localhost:4000/cart
```

Prerequisites: Erlang 27, Elixir 1.18 (`.tool-versions`), PostgreSQL.

## The workflow rule

**Change `manifest.ex` first, then run `mix zc.gen` and commit both files.** The committed
`generated.ex` is source you review in the PR — it is the code you shipped. `mix zc.gen --check`
guarantees the two never diverge.

## Attribution

Reference scaffold based on the [Amazin Phoenix LiveView tutorial](https://github.com/tylerwray/amazin)
by Tyler Wray. Architecture, feature-file shape, generator, effect model, tests, and docs are
original. [MIT License](LICENSE).
