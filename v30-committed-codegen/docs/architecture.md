# V30 Architecture

## One sentence

V29.1's manifest-wired feature files, with the glue **generated into a committed file** by
`mix zc.gen` instead of an invisible `@before_compile` — no runtime routing, no cascade, no
web-layer macros; the composition is three plain files you can read top to bottom.

## The layers

```
CartPage (hand-written LiveView)             ← mount + irregular clauses + run/2 + thin delegation
  ├─ CartPage.Manifest (plain data module)   ← THE DIAGRAM: features / reactions / action_views
  ├─ CartPage.Generated (committed .ex)      ← Session struct, apply_fact/2, page_event/4, render,
  │                                            per-slot assigns — written by `mix zc.gen`
  ├─ ActionViews (IndexView, CheckoutView)   ← cross-feature composites + step branching
  └─ EffectInterpreter                       ← the one place effect data meets Phoenix
Features (application layer, one file each)  ← pure module + Intents (+ Facts) + Components
Cart aggregate                               ← unchanged from V28 (single source of truth)
Effects (data structs) · Domain abstractions · Foundation   ← unchanged from V28
```

## Data flow for one event

```
click "Remove"                                            (browser)
  → handle_event("remove_item", …)                        (CartPage: delegates to Generated)
  → Generated.page_event("remove_item", params, socket, &run/2)   (GENERATED clause: casts item-id)
  → run(socket, fn s -> CartItems.Intents.remove_item(s, %{item_id: 1}) end)   (CartPage's run/2)
  → CartItems.Intents.remove_item(session, args)          (hand-written intent, owns :cart slot)
      returns {session', [stream_delete, push], [%Facts.ItemRemoved{item: …, item_id: 1}]}
  → Generated.apply_fact(session', %CartFacts.ItemRemoved{} = fact)   (GENERATED from the react entry)
      payload = Map.from_struct(fact)                     (or the wire's transform: fn)
      → Undo.Intents.capture_removed(session'.undo, payload)   (slot-scoped reaction — never
      returns {session'', effects ++ [start_timer, flash]}      sees the emitter's struct)
  → Generated.put_session (per-slot assigns + @cart render_data) → EffectInterpreter.apply_all
```

Every arrow is a plain function call — and now every arrow through `Generated` is **committed
source** you can open, grep, and set a breakpoint in. Reactions cannot emit further facts (single
level); a needed chain is an ownership-restructuring signal, not a reason for cascade depth.

**Typed facts (from V29.1).** A fact is a struct in the emitter's `Facts` sibling module
(`@enforce_keys`). Compile-time checking covers all manifest links: fact construction (struct
keys), fact reference in the manifest (alias expansion at ordinary compile time), and the reaction
target/intent calls (literal remote calls in `generated.ex` → "undefined or private" warnings). The
reactor-side boundary is a **projection**: `Map.from_struct/1` by default, or the target's
`transform:` when vocabularies differ (`MovedToCart` translates `saved_item` → `item`). Reactors
never alias an emitter — zero-coupling by construction, translation owned by the manifest.

## The one macro (the whole magic budget)

V30 has a **single** macro, in the core — the web layer has none.

| Macro | Lives in | Provides |
|---|---|---|
| `use ZeroCoupled.Feature.Intents, slot: :x` + `intent name, params: […]` | `zero_coupled/feature/intents.ex` | `put_slot/2` (Map.replace! — raises on wrong slot), `__slot__/0`, `__intents__/0` (intent metadata: name + cast spec, no behaviour) |

Everything V29 generated via `@before_compile` is now produced by
`ZeroCoupled.Gen.PageGenerator.generate/1` — an ordinary function that emits the same quoted forms,
stringifies them, formats them, and writes a file. Because it is a plain function it has a **unit
test** (`page_generator_test.exs`) driven by a minimal fixture manifest, which the macro never had.

Escape hatches: irregular events are ordinary `handle_event` clauses in the hand-written CartPage,
ending with `def handle_event(e, p, s), do: Generated.page_event(e, p, s, &run/2)`. `render/1` and
`run/2`/`effect_opts/0` are hand-written too — no "generate only if absent" cleverness needed,
because nothing is injected into CartPage at all.

Failure modes stay loud: duplicate intent owner = **generation-time** error; missing `:index`
action view = generation-time error; undeclared fact = runtime raise; unknown event = runtime raise
with guidance; wrong slot write = `Map.replace!` KeyError; `PageCheck.verify/1` checks the
manifest's references in one test line; **stale `generated.ex` = `mix zc.gen --check` build
failure**.

## Ownership model — unchanged from V29.1

| Code | May read | May write | Communicates outward via |
|---|---|---|---|
| Intent `(session, args)` | any slot | **own slot only** (`put_slot/2`) | effects + facts |
| Reaction `(slot, payload)` | own slot only (by signature) | own slot only | effects |
| Manifest | everything | — | declares all fact wiring (plain data) |
| ActionView | slot assigns (`@cart_slot`…), `@cart` (render_data) | — | markup |

## L5: the render_data presentation port + per-slot assigns

`cart: {CartItems, render: :render_data}` makes `Generated.put_session/2` maintain a `@cart` assign
= `CartItems.render_data(session.cart)` — a plain map of display-ready values. Composites read
`@cart` and survive aggregate field renames.

`put_session/2` also assigns **every slot individually** (`@cart_slot`, `@undo_slot`, …), and
ActionViews read *only* slot assigns — never `@session`. Because immutable session updates are
structurally shared, an untouched slot is the *same heap term* and `assign/3` no-ops on equal
values: LiveView's change tracking then skips the template regions and function-component call sites
of every feature an event didn't touch.

The derived `@cart` assign is additionally **gated**: `put_session` recomputes
`CartItems.render_data(session.cart)` only when the cart slot's term actually changed — an O(1)
`:erts_debug.same/2` identity check against the previous `@cart_slot` — so an event that touches
only another feature does *zero* cart-presentation work (generated as a `render_stale?/3` guard in
`generated.ex`). Together this delivers per-feature render isolation with plain function components
(no LiveComponents), putting V30 at **R1 = 5** — the supplementary runtime-efficiency ceiling (see
`Q-v30-direction-analysis.md`, Appendix 2). The pipeline stays diff-neutral: pure computation
before render; effects are native LiveView calls.

## Differences from V27 · V28 · V29.1, in one table

| | V27 | V28 | V29.1 | V30 |
|---|---|---|---|---|
| Cross-feature routing | runtime table + dispatcher, depth-5 cascade | explicit calls in Session fns | manifest `react` **compiled** by macro, single level | manifest `react` **generated to a committed file**, single level |
| Glue visibility | interpreted at runtime | hand-written | generated, dumpable, snapshot-tested | **committed source**, PR-reviewed, `--check`-enforced |
| Web-layer macros | 1 (capsule) | 0 | 3 (Page + feature/react/action_view) | **0** |
| Total macros | several | 0 | 3 | **1** (intent metadata) |
| Generator testability | — | — | none (macro) | **unit-tested function** |
| App-layer growth | wiring table + capsules | Session monolith | manifest ~1 line/feature | manifest ~1 line/feature (plain data) |
| Composition testable purely | via dispatcher | session_test | `run_intent` on the real page | `run_intent` on the real page |
