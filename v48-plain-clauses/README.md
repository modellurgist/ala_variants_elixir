# V48: Plain clauses

V45 with only the two changes the 2026-10-02 stricter readings asked for, and no Features layer: the
test of whether a full ALA Checklist score can stay at familiarity 4. Blog post:
[V48, plain clauses](https://getdown.dev/blog/intro-to-v48-plain-clauses/).

**Score:** full checklist by hand **100** under the 2026-10-02 readings (V45: 99). `ala_lint` 100/A
default, 100/A strict (10 of 10 checked rules met), 99/A super-strict. **119 tests, 0 failures**.
Familiarity 4 of 5. Zero message hops.

## What it changes from V45

- **`State`, not `Features`.** The coded state modules (`Cart`, `Undo`, `Checkout`, …) are stateful
  domain abstractions in Spray's terms; his features are compositions (§2.2). A rename, nothing else.
- **A record form instead of `FormComponent`.** The product pages place a generic `record_form`
  domain UI component and wire a `RecordEdit` state to `SaveProduct` with the same `wire/3` clauses
  and `Steps` runner as the cart page. Nothing page-specific keeps its own state or handlers.

Everything else is V45: plain LiveView pages, `{state, outputs}` modules in the page's assigns, one
`wire/3` clause per port, named store-work instances, and `Wiring.gaps/1`.

## Why no Features layer

Spray adds one when the application "will go over the 500 line complexity limit" (§2.2). The cart page
is 484 lines with its template and the portal 308, so neither needs it. When a page outgrows that,
[V46](../v46-feature-stories) is the same design split into user stories.

## Run it

```bash
cd v48-plain-clauses
mix deps.get
mix test
```
