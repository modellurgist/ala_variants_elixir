# V50: Plain LiveView

V48 without its one piece of unfamiliar vocabulary: the test of whether a full ALA Checklist score can
be reached at familiarity 5 with no relays between components. Blog post:
[V50, plain LiveView](https://getdown.dev/blog/intro-to-v50-plain-liveview/).

**Score:** full checklist by hand **100**. `ala_lint` 100/A at every tier (10 of 10 checked rules met
under `--strict`). **153 tests, 0 failures**, every declared output routed under the suite. Familiarity 5 of 5 (judgement). No LiveComponents, so no
relays between them; every update runs inside one `handle_event`, and only the payment is a task.

*Since 2026-10-19:* the linter's clone check (duplicated logic, R7) found five duplicates. Three of
them were two concepts written twice, now one abstraction each: `Checkout` and `PortalSubmit` share a
step machine (`Transitions.fire/2`, `jump/2`, `move/2`, configured from the page's flow table and URL
edges), and `Cart` and `OrderLines` share one row projection (`Lines.row/2`). Two are accepted in the
code with `ala:accept clone`: the `set_stock` input's result-to-outputs shape, and two pages wiring
their own flow's `step` and `form`. 100 at every tier again; `lint.exs` lists what remains, all
unscored.

*Defect fixes, 2026-10-19 (ported from V51B, each with a regression test that failed first):* undo on
the portal now flashes "Item restored" (R4.2); the info and error flashes have distinct DOM ids
(`flash-info`, `flash-error`); and a removal is written at once as a hold (`removed_at`, a new
migration) that every read skips. So paying or submitting inside the undo window no longer deducts
stock for or records the removed line, and a page closed inside the window no longer brings the line
back (R4.3): the next mount, or the order, makes an elapsed hold final.

*Save for later, 2026-10-19 (five regression tests, three on the page and two on the store, each
failing first):* saving moved the line out of the cart only in memory, so paying (which charged the right
amount) deducted stock for it and recorded it, and a reload put it back in the cart. A saved line is now written as such (`saved_at`, a
second migration): `Carts.list_items` skips it, `Carts.list_saved` loads the Saved tab on mount, and
"Move to cart" clears the mark (R3.8, R1.4, R5.5). A saved line stays with a paid cart, outside its
order. Adding a product whose line is saved brings that line back into the cart.
`Carts.apply_change/1` now has five kinds, accepted in the code with `ala:accept vocabulary`.

*Later (2026-10-21): a change feed.* Outside change (another session's purchase, a staff
edit at /products) is now one programming-paradigm part, `GoodDealWeb.Paradigms.ChangeFeed`, instead of a
`handle_info` clause per kind of change on each page. A page lists its feed as a part,
`feed: ChangeFeed.new(Catalog.changes_topic(), [:stock])`, attaches it in `mount/3`, and wires its ports like
any other output: `wire(s, :feed, {:stock, change})` runs `Cart.set_stock` on the cart, both
`OrderLines` and `PortalCatalog` on the portal, and refreshes the row on /products. The publish side is
another instance on the same topic: `SettleOrder`'s `announce` and the product pages' `saved` clauses.
A fact is a kind and a product id with at most one value. `Foundation.Broadcast`, the `Subscribed`
hook and `SaveProduct`'s own broadcasting are gone. The move closed a gap: a staff stock edit at
/products was broadcast as `product_updated`, which the cart and portal ignored, so an open cart never
showed it (R3.14, R6.8). The product pages' `saved` clause now also publishes the stock fact, and a
test that failed without that line covers it. Eight tests added (four on `ChangeFeed` itself), one
removed with `Broadcast`.

## The wiring as it ran (added 2026-10-16)

`Steps.run/4` records, when a test run has the trace on, the hop from whatever output is being routed
(or the browser, a timer, a task, PubSub) to the part it reached, and a landing when a `wire/3`
clause ran no other part. No page changed: the page `Steps.run` was called from is read off the
`wire` function it was handed. `ExUnit.after_suite` writes `docs/diagrams/running/*.md` and fails the
run if a declared output never routed. Its first run found four: the cart's wishlist removal and
out-of-stock payment, the portal's undo expiry and empty review, each wired and untested; the suite
has them now. `lint.exs` holds the layer map (100 at every tier).

## What it changes from V48

- **No named instances.** The configured store-work instances (`AddLine`, `Charge`, `SettleOrder`,
  `PlaceOrder`) are plain assigns, and a clause names the call it makes:
  `Steps.feed(:cart, &Cart.receive/2, &AddLine.run(s.assigns.add_line, &1), product, &wire/3)`.
- **LiveView's own API for the rest.** The payment is `start_async(s, :payment, fn -> Charge.call(charge, payment) end)`,
  its outcome routed by `handle_async/3`; settling the order is a plain call before `push_navigate`.
- **`Steps` is `run/4` and `feed/6`** (plus the stream, patch and timer landing points). `call`,
  `async` and the instance lookup are gone.

What it gives up: a misnamed instance is no longer a loud "no configured instance" error, and clauses
read configured instances from assigns again (as V38-max and V49 do). Store work stays synchronous, as
in V48.

## Run it

```bash
cd v50-plain-liveview
mix deps.get
mix test
```
