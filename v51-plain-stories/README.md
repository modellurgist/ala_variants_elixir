# V51: Plain Stories

V50 with Spray's Features layer and smaller state abstractions: the test of whether a page can have
user-story modules and meet every rule `ala_lint` checks at its strictest tier, while staying close to
plain LiveView.

**Score:** full checklist by hand **100**. `ala_lint` 100/A at every tier, and **10 of 10 checked rules
met under `--super-strict`**, the first variant to do so. **158 tests, 0 failures**, every declared output routed under the suite. Familiarity 4 of 5
(judgement). No LiveComponents, so no relays between them.

*Since 2026-10-19:* the linter's clone check (duplicated logic, R7) found four duplicates across
modules. Three were one concept written twice and are now one abstraction each: the step machine
`Checkout` and `PortalSubmit` both ran (fire an event along the flow table, honour a URL jump) is
`Transitions`' machine, and the displayed row `CartLines` and `OrderLines` both projected is
`Lines.row/2`. The fourth, `set_stock` in both, is accepted in the code: the shared part is already
`Lines.set_stock`. Still 100 at every tier.

*Fixes, 2026-10-19 (ported from V51B):* undo on the portal now flashes "Item restored" (R4.2); the
info and error flashes have distinct ids (`flash-info`, `flash-error`); and a removed line is held in
the store (a `removed_at` column, migration `20261019120000`) instead of left as a live row, so paying
or submitting while a removal is undoable no longer deducts or records it, and a removal survives the
page closing (R4.3): `Carts.load_items/2` makes elapsed holds final when either editing story mounts,
and `Orders.create/1` makes all of them final. Adding a product whose line is held replaces the held
line. Each fix has a regression test that failed first. Run `mix ecto.migrate` for the dev database.

*Fix, 2026-10-19:* save for later wrote nothing, so a saved line stayed a live cart row: paying
charged nothing for it but still deducted its stock and kept it in the order's lines, and a reload put
it back in the cart. It is now marked in the store (a `saved_at` column, migration
`20261019130000`): `CartLines.save_for_later` sends `{:saved, cart_id, item_id}` on `changed`,
`Carts.list_items/1` (the cart's lines, settlement, the order) leaves saved rows out,
`Carts.list_saved/1` reads them into the Saved tab when `SaveForLater` mounts, and moving one to the
cart sends the existing `{:kept, ...}`, which now clears both marks. Adding a product whose line is
saved brings that line back into the cart, one more. Seven regression tests failed first.

## The wiring as it ran (added 2026-10-16)

`Steps.to/7` and `Steps.out/5` record every hop a page routes while the test suite runs (a browser
event into a story, a story's output into another story, an output landing on the page); the pages'
`to/4` and `out/1` became one-line calls into them. `ExUnit.after_suite` writes
`docs/diagrams/running/*.md` and fails the run if a declared output never routed. The first run
found the cart's tab switch and the portal's undo expiry wired and untested; the suite has both now.
`lint.exs` holds the layer map (100 at every tier).

## What it changes from V50

- **Stories.** Each page composes user stories (`GoodDealWeb.Stories`): `EditCart`, `UndoRemoval`,
  `SaveForLater`, `KeepWishlist` and `CheckOut` on the cart page; `EditOrder`, `BrowseCatalog`,
  `SubmitOrder` and the same `UndoRemoval` on the portal. A story is a module of plain functions:
  `parts/0`, `ports/0` and `events/0`; `mount/3`; `input/4` for its input ports;
  `handle_event/4` for the events its own view fires; private `wire/4` clauses wiring its parts;
  function components for its view. It runs on V50's `Steps.run/4` and `Steps.feed/6`. There is no
  story struct, runner or behaviour.
- **The page wires stories.** A story sends an output by calling the `out` function it's given
  (the page's `wire/3` with the story's key bound), so it never knows its key, the page or another
  story. The page's `wire/3` clauses are the links between stories; `to/4` sends to a story's input.
  Each story handles its own browser events; the page dispatches with one clause per story
  (`when event in @edit_cart_events`), built from the story's `events/0`. The page names the timer
  and task a story starts (`timer: :undo`, `task: :payment`), so no name is agreed between two modules.
- **Smaller state.** `State.Cart` (19 public functions) and the `GoodDeal.Cart` aggregate are replaced
  by `CartLines` (the lines and gift-wrap marks), `Promo` (a code, checked and kept) and `CartTotals`
  (the priced summary, joining the lines' amounts and quantities, the discount and the shipping
  method). They are wired to each other inside `EditCart`. `OrderLines`' helpers are private.
- **Checks.** `Wiring.gaps/1` covers pages (`wire/3`) and stories (`wire/4`); `input_gaps/1` checks each
  story's input clauses; `event_gaps/1` checks that every event a story's view fires is declared and
  handled by that story; a test checks that no two stories on a page claim an event. The drawer
  draws a page's links between stories and, with `mermaid_story/1`, one story's inside.

What it costs: a story is a new kind of module to learn (V50 has none), the cart page's checkout
"Pay" goes out of `CheckOut` and back through the page to `EditCart` for the cart's lines, and stories
on one page share the page's assigns, so two stories choosing the same part key would collide. Nothing
checks that yet.

## Run it

```bash
cd v51-plain-stories
mix deps.get
mix test
```
