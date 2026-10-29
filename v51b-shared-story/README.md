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
tier, 10 of 10 checked rules met under `--super-strict`** (since 2026-10-19, when the linter stopped
reading `PriceOrder.mount/3`'s `assign` of a built value as a pass-through). **152 tests, 0 failures**, every declared
output routed under the suite. Familiarity 4 of 5 (judgement), as V51.

*Since 2026-10-19:* the linter's clone check (duplicated logic, R7) found the step machine written
twice, in `Checkout` and `PortalSubmit` (moving along the flow table, and the URL's allowed jumps).
Both decisions now live in the state-machine paradigm, `Transitions.next/3` and `Transitions.jump/3`;
each part keeps only setting its step and sending its own `step` output. No clones remain.

*Since 2026-10-19:* save for later is stored. A saved line used to stay a live `cart_items` row, so
payment bought it and a reload put it back in the cart. `CartLines` now marks it
(`{:aside, :saved, ...}`, a `saved_at` column, as a held removal is marked `removed_at`), the cart's
reads and settlement leave it out, `SaveForLater` loads the Saved tab from `Carts.list_saved/1`, and
a line moved back is `{:kept, ...}` like an undone removal. Run `mix ecto.migrate` on an existing
dev database.

*Since 2026-10-21:* outside change is a part. `Paradigms.ChangeFeed` (programming-paradigms layer) is
mounted by a page as `feed`, configured with a topic and the facts it wants, and wired like a story:
`feed.stock → edit_lines.stock` on the cart, `→ edit_lines.stock, catalog.stock` on the portal,
`feed.product`/`feed.stock` into the product list. A page that changes a product hands it to
`ChangeFeed.publish/2`: the checkout's settlement (`SettleOrder`'s `announce`) and both product pages'
saves. `Foundation.Broadcast`, `Paradigms.Subscribed` and the pages' `handle_info` clauses for
catalogue messages are gone. The move closed a gap: a staff stock edit at /products never reached
an open cart or portal, which ignored `:product_updated`; the product pages now publish `:stock`
with `:product`.

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
