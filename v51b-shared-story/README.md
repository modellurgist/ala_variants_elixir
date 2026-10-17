# V51B: Shared Editing Story

V51 (`../v51-plain-stories`) with one editing story for both pages: `EditLines` edits the lines of the
shopper's cart and the buyer's order, placed by each page with its own row component, stream name
and stock rule, with pricing in a story of the page's own (`PriceCart`: promo, shipping, gift wrap,
checkout; `PriceOrder`: volume tiers, review). `OrderLines` is gone; `CartLines` serves both, and a
new `OrderTotals` prices the portal. A page may list outputs of a shared story it leaves open in
`grounded/0`, which the wiring check and the trace both honour. It is the Elixir counterpart of
Ruby's V05 feature placed by two pages. The B in the name says it is an alternative organisation
of V51's Features layer, not a step beyond it: V51 shows two small editing stories that stay
separate, V51B one story two pages share. Both are legitimate ALA positions (R7 asks for the fewest
abstractions, not the most reuse) and the pair is kept so the two shapes can be compared on the
same requirements.

The running trace (`Steps.to/7`, `Steps.out/5`, `Trace`, the after-suite report and
`docs/diagrams/running/`) was first built in this variant, when it was called V52, and now lives in
V50 and V51 as well; see `../v51-plain-stories/README.md` for it.

**Score:** full checklist by hand **100**. `ala_lint` with `lint.exs`'s layer map: **100/A at every
tier, 10 of 10 checked rules met under `--super-strict`**. **129 tests, 0 failures**, every declared
output routed under the suite. Familiarity 4 of 5 (judgement), as V51.

## What it changes from V51

- **`EditLines`** is the one editing story. Its part is `CartLines`, which gained an absolute
  quantity and a line arriving at a quantity as clauses of functions it already had, so its public
  surface stays at twelve. Its events are the union of both pages' line events.
- **The row is the page's.** `EditLines.rows` takes the page's row component as `row` and what that
  row needs as `row_attrs`; the story renders each row through it, passing the event names it owns,
  so V51's R5 ownership holds and the page owns what a line looks like (§7.14).
- **Pricing is the page's story.** `PriceCart` holds `Promo` and `CartTotals`; `PriceOrder` holds
  `OrderTotals`. Each takes `contents` in and sends `summary` out: one hop per line change that V51
  kept inside `EditCart`.
- **Grounded outputs.** The portal's rows offer no save, wishlist or checkout, so three of
  `EditLines`' outputs can never fire there; the page says so in `grounded/0`.

What it costs: one more hop per line change on each page, visible in the running drawing; a story
that renders the page's row through a function it is handed; thirty more lines on the cart page;
250 fewer non-blank lines in `lib/` with `EditOrder` and `OrderLines` gone.

## Run it

```bash
cd v51b-shared-story
mix deps.get
mix test
cd ../../ala_lint_elixir && mix run ../ala_variants_elixir/v51b-shared-story/lint.exs   # every tier, with the layer map
```
