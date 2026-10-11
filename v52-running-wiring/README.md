# V52: Running Wiring

V51 with its wiring recorded **as it runs**: `Steps.to/7` and `Steps.out/5` note every hop a page
routes while the test suite runs (a browser event into a story, a story's output into another
story, an output landing on the page), `Trace.mermaid/1` draws each page from those hops, and the
suite fails if a declared output never routed anywhere. The drawing can't drift from the code
because it is the code that ran, which is Spray's technique for the diagram and the checklist's R8
coverage test in one. The source-parsed `Drawing` stays for a story's inside. `docs/diagrams/running/`
holds the result of the last run.

Extended on 2026-10-11 with **one editing story for both pages** (the design once called V53, kept
in this variant): `EditLines` edits the lines of the shopper's cart and the buyer's order, placed by
each page with its own row component, stream name and stock rule, with pricing in a story of the
page's own (`PriceCart`: promo, shipping, gift wrap, checkout; `PriceOrder`: volume tiers, review).
`OrderLines` is gone; `CartLines` serves both, and a new `OrderTotals` prices the portal. Pages may
list outputs of a shared story they leave open in `grounded/0`, which the wiring check and the trace
both honour. The same day, scoring with a layer map (`lint.exs`, kept here) found the trace's hop
marker in the process dictionary (R4, hidden state); it now rides in the socket's private map.

**Score:** full checklist by hand **100**. `ala_lint` with `lint.exs`'s layer map: **100/A at every
tier, 10 of 10 checked rules met under `--super-strict`**. **129 tests, 0 failures**, every declared
output routed under the suite. Familiarity 4 of 5 (judgement). Everything else is V51's
(`../v51-plain-stories/README.md`), summarised below.

## What it keeps from V51

- **Stories.** Each page composes user stories (`GoodDealWeb.Stories`): `EditLines`, `PriceCart`,
  `UndoRemoval`, `SaveForLater`, `KeepWishlist` and `CheckOut` on the cart page; `EditLines`,
  `PriceOrder`, `BrowseCatalog`, `SubmitOrder` and `UndoRemoval` on the portal. A story is a module of plain functions:
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
  method). The lines are wired inside `EditLines`; promo and totals inside `PriceCart`.
- **Checks.** `Wiring.gaps/1` covers pages (`wire/3`) and stories (`wire/4`); `input_gaps/1` checks each
  story's input clauses; `event_gaps/1` checks that every event a story's view fires is declared and
  handled by that story; a test checks that no two stories on a page claim an event. The drawer
  draws a page's links between stories and, with `mermaid_story/1`, one story's inside.

What it costs: a story is a new kind of module to learn (V50 has none), the cart page's checkout
"Pay" goes out of `CheckOut` and back through the page to `EditLines` for the cart's lines, and stories
on one page share the page's assigns, so two stories choosing the same part key would collide. Nothing
checks that yet.

## Run it

```bash
cd v52-running-wiring
mix deps.get
mix test
cd ../../ala_lint_elixir && mix run ../ala_variants_elixir/v52-running-wiring/lint.exs   # every tier, with the layer map
```
