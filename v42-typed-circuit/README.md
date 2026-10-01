# V42: Typed circuit, sourced from a diagram

The same storefront and B2B portal as V39–V41 (the V35 requirements), built as V40's circuit of
instances made stricter.
What V40 left implicit, V42 declares and checks: every instance's ports and their paradigm types,
every wire, every deliberately unused output, and every place a timer or async job feeds back in.
Each page's circuit lives in its own **diagram module**, which is validated when the page mounts and
drawn to Mermaid from the same value that runs.

**Score:** `ala_lint` 98/A default, 97/A strict, 97/A super-strict (V40: 98/97/95), on the family
layer map with the diagram modules added to the application layer. No R1 or R11 finding.
Full checklist by hand: 90.
**87 tests, 0 failures.**

## What changed from V40

1. **Declared, typed ports.** The `Step` protocol gained `ports/1` (inputs and outputs with a paradigm
   type such as `:item`, `:summary`, `:row_change`) and `feeds/1` (the `{instance, input}` targets a
   timer or async job pushes back into). Features declare `ports/0`; the `Adapter` reports them; every
   sink declares its own.
2. **`Circuit.validate!/1`**, run in each page's `mount/3` and in `test/zero_coupled_web/diagrams_test.exs`.
   It raises on a wire to an unknown instance or port, a wire between different types, an output that
   is neither wired nor grounded (`Circuit.ground/2`), a timer or async target that isn't a declared
   input, and an anonymous function anywhere in an instance's configuration. The test seeds each of
   those mistakes and checks it is caught.
3. **Diagram modules.** `ZeroCoupledWeb.CartDiagram` and `PortalDiagram` hold each circuit and the
   store's literals as one data expression. The pages shrink to framework glue: mount the validated
   circuit, turn the URL into a step, route PubSub and the runner's messages, and render (cart page
   294 → 140 lines, portal 163 → 62). There is no catch-all `handle_info`; each page ignores
   `ProductSaved` explicitly.
4. **Named captures only.** V40 configured five instances with closures (`&add_line(cart_id, &1)`,
   `fn _ -> Products.list() end`, ...). They are gone: order placement and line creation are the
   domain abstractions `PlaceOrder` and `AddLine`, which implement `Step` and do their own I/O
   through the stores they are configured with; `FromStore` accepts a zero-arity read; persistence is
   `&Carts.apply_change/1`. Every function in a circuit is a named capture, so the compiler and
   `ala_lint` see every call, and the drawing can label it (`Function.info/1`).
5. **Drawings.** `mix circuit.draw` writes `docs/diagrams/cart.mmd` and `portal.mmd`; `--check` (and
   a test) fails when a committed drawing no longer matches the diagram.
6. **From the V41 revision:** domain rules configured once and called configuration-first
   (`CalculateShipping.new(@rates)`), `ShippingInfo` folded into `CalculateShipping`, and the
   `Subscribed` `on_mount` hook instead of `if connected?(socket)` in `mount/3`.

## What it costs

- **Lines:** 4,913 in `lib/` against V40's 4,464 (+449). Validation is about 80 lines of
  `Circuit`, the port declarations about 40 across the sinks plus a `ports/0` per feature, the
  drawing about 60, and the rest is the moved diagrams and the two domain abstractions.
- **Concepts:** everything V40 asked a reader to learn (a circuit, the `Step` port, sinks, a runner,
  UI instances that emit into the circuit), plus port types, grounds, feeds, and diagram modules.
  Familiarity stays at 2 of 5.
- **Hops:** unchanged from V40. A click is still component → page → circuit → component.
- **What validation can't see:** a UI instance feeds a named input (`Emitter.feed(socket, :cart,
  {:remove, ...})`) from inside a LiveComponent, outside the circuit, so a typo there is still found
  only when the event fires.

## Layout

- `lib/zero_coupled/ports/step.ex` — the port protocol (`push/2`, `ports/1`, `feeds/1`).
- `lib/zero_coupled/paradigms/` — `Circuit` (with `ground/2`, `validate!/1`), `Adapter`, the sinks,
  `Transitions`, and `Drawing` (Mermaid).
- `lib/zero_coupled/domain/` — the configured pricing rules, `AddLine`, `PlaceOrder`.
- `lib/zero_coupled/features/` — the pure features, each with `ports/0`.
- `lib/zero_coupled_web/diagrams/` — `CartDiagram`, `PortalDiagram`, and `Diagrams` (what gets drawn).
- `lib/zero_coupled_web/pages/` — the two pages.
- `docs/diagrams/*.mmd` — the generated drawings.

## Running it

Needs PostgreSQL (see `config/test.exs`).

```bash
mix deps.get
mix test                 # 87 tests
mix circuit.draw         # regenerate docs/diagrams/*.mmd
mix circuit.draw --check # fail if a drawing is stale
```
