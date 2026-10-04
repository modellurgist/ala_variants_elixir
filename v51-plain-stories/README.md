# V51: Plain Stories

V50 with Spray's Features layer and smaller state abstractions: the test of whether a page can have
user-story modules and meet every rule `ala_lint` checks at its strictest tier, while staying close to
plain LiveView.

**Score:** full checklist by hand **100**. `ala_lint` 100/A at every tier, and **10 of 10 checked rules
met under `--super-strict`**, the first variant to do so. **126 tests, 0 failures.** Familiarity 4 of 5
(judgement). No LiveComponents, so no relays between them.

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
