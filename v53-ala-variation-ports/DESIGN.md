# V53 design: ALA ports only at variation points

## The rule (subset 3)

V53 is V52 under subset 3 of `ala_lab/docs/Q-ala-light-subsets.md`, as read in the subset-3 brief.
It is a checklist reading, not Spray's wording.

- A variation point is a part placed by two or more compositions today, or a programming paradigm
  (the wiring itself, `ChangeFeed`, `Steps`, `Transitions`). Only variation points declare ports and
  are wired. A second placement that might come later doesn't count; the second placement has to
  exist, so the rule can be checked.
- Every other part is called. It keeps its layer and its configuration (literals still come from
  the page, R3), but the page calls it and uses what it answers. It has no output ports, no wire
  arm, and nothing relays its result through another part. A stateful part placed once (a step
  machine, a list) is a struct the page holds; each call answers the new struct and its result.
- A story placed by one page folds into that page. A story placed by two pages stays a story with
  ports.
- The rest of the checklist holds as in V52: R1, no peer calls, R3, R6, R7, R8, and R11 as advice.

The reason is the 2026-10-22 run (`ala_lab/docs/change-cost-light-2026-10-22.md`). V52's dearest
step paid to move a priced summary along wires through `SubmitOrder`, `CheckOut`, `Checkout` and
`PortalSubmit`, each placed once.

## Inventory

Every part, story or paradigm V52 gave ports, who placed it, and what it is now, with `DraftOrder`,
added since.

| Part | Placed by | Variation point | In V53 |
|---|---|---|---|
| `Stories.DraftOrder` (2026-10-23) | cart page, portal page | yes | wired; holds the next three on both pages |
| `Stories.EditLines` | `DraftOrder` (so once per page) | yes, by judgement, as `CartLines` (below) | wired inside `DraftOrder` |
| `Stories.UndoRemoval` | `DraftOrder` (once per page) | yes, by judgement, as `Undo` (below) | wired inside `DraftOrder` |
| `Paradigms.ChangeFeed` | `DraftOrder`, product list (publish also on cart checkout and product show) | yes, paradigm | wired (inside `DraftOrder` on cart and portal) |
| `State.RecordEdit` | `ProductLive.Index`, `ProductLive.Show` | yes | wired |
| `State.CartLines` | `EditLines` (so once per page that places it) | yes, by judgement (below) | wired inside `EditLines` |
| `State.Undo` | `UndoRemoval` (once per page) | yes, by judgement (below) | wired inside `UndoRemoval` |
| `Stories.PriceCart` | cart page | no | folded into the cart page |
| `Stories.CheckOut` | cart page | no | folded into the cart page |
| `Stories.SaveForLater` | cart page | no | folded into the cart page |
| `Stories.KeepWishlist` | cart page | no | folded into the cart page |
| `Stories.PriceOrder` | portal page | no | folded into the portal page |
| `Stories.BrowseCatalog` | portal page | no | folded into the portal page |
| `Stories.SubmitOrder` | portal page | no | folded into the portal page |
| `State.CartTotals`, `State.Promo` | `PriceCart` | no | called by the cart page |
| `State.Checkout` | `CheckOut` | no | called by the cart page |
| `State.SavedItems` | `SaveForLater` | no | called by the cart page |
| `State.Wishlist` | `KeepWishlist` | no | called by the cart page |
| `State.PageUI` | cart page | no | called by the cart page |
| `State.OrderTotals` | `PriceOrder` | no | called by the portal page |
| `State.PortalCatalog` | `BrowseCatalog` | no | called by the portal page |
| `State.PortalSubmit` | `SubmitOrder` | no | called by the portal page |

`Steps`, `Transitions`, `Wiring`, `Trace` and `Drawing` are paradigms and keep their shape. The
domain functions (`SettleOrder`, `PlaceOrder`, `AddLine`, `Charge` and the rest) had no ports and
were already called.

`CartLines` and `Undo` are a judgement call. Each is placed once in source, inside a story, but that
story is placed by both pages with each page's configuration (cart id, stock rule, stream, window),
so at run time there is one `CartLines` per page. Their outputs are the story's outputs, one for
one. Turning them into calls would leave the story translating returned values back into the same
outputs, a relay the rule exists to remove. They keep `ports/0` and the story's `wire/4` arms.

## What changed

- Seven stories deleted (627 lines). Their views moved into the pages' `render/1`, their events into
  the pages' `handle_event/3`, their flow tables, URLs and blocked messages to the top of the page.
- The nine called state parts lost `ports/0` and answer values: `Checkout.pay/2` answers
  `{:ok, checkout, payment}` or `{:blocked, reason}`; `PortalSubmit.submit/2` answers
  `{:ok, flow, po}` or `{:error, changeset}`; `CartTotals` and `OrderTotals` answer a new struct and
  price it in `summary/1`; `Wishlist.toggle/2` answers the change; `SavedItems.move_to_cart/2` and
  `Wishlist.remove/2` answer what they took. Four functions that only re-emitted a value the page
  already held are gone (`CartTotals.start_checkout`, `OrderTotals.request_review`,
  `Checkout.show_form`, `Checkout.validate`), and `Wishlist.take` is `remove`, since the page decides
  what happens to the product. 584 lines went to 410.
- The S04 path is now short. Paying reads `@summary` and the lines `EditLines` answers on
  `checkout_requested`; submitting places the order with the PO `PortalSubmit.submit/2` answers.
  Nothing travels through a part placed once.
- Each page has `@parts` of three (`edit_lines`, `undo`, `feed`; one, `draft`, since 2026-10-23). The wiring test checks two
  stories instead of nine; the trace's "every declared output routed" check covers what stays wired.
  The cart lost one routed hop (`check_out.pay_requested → edit_lines.request_checkout` is now a
  browser event the page sends to `edit_lines`) and the `ui: :tab` output.
- `Drawing` now draws a part called inside a page function's arguments as a dotted call
  (`edit_lines -.->|"contents"| call CartTotals.contents`), so the source drawing still shows where a
  wired output goes when a called part takes it. The running drawings show the wired hops only.
- Unit tests of reshaped parts assert returned values. One test went:
  `CartTotals` "starting checkout hands over the summary", which pinned the deleted
  `start_checkout`; the cart page's checkout tests cover what it did. One test came: the drawing of
  a called part. No LiveView test changed.

## One story for what both pages did alike: `DraftOrder` (2026-10-23)

The clone below was the rule's own case: whatever both pages do the same way is a concept placed by
two pages, so it is a variation point. Both pages mounted `UndoRemoval`, `EditLines` and `ChangeFeed`
with the same configuration shape and wired them to each other with the same clauses
(`removed → capture`, `restored → receive`, `expired → confirm_removal`, `feed.stock → stock`).
`Stories.DraftOrder` now holds that: an order being drafted, its lines edited, a removal held while
it can be taken back, stock kept current. Each page mounts it once, as `draft`, with its own cart
id, stream, timer name, window and topic; the words, the row and the flashes stay on the page.

- **Ports.** In: `request_checkout`, `receive`, `add_product`, `add`, `expire` (the page's timer
  message). Out: `contents`, `saved`, `line`, `checkout_requested`, `restored`, `pending`, `stock`.
  Events: its two stories' (`EditLines.events() ++ UndoRemoval.events()`), dispatched to whichever
  owns the event. The pages still render `EditLines.rows` and `UndoRemoval.view` themselves; the
  story has no view of its own, so the wiring test checks its events against its parts' instead of
  reading them from its templates.
- **One window, two uses.** `EditLines` took `hold_ms` and `UndoRemoval` `window_ms`; both pages
  passed `Catalog.undo_window_ms()` to each. The story takes `window_ms` once and gives it to both,
  because a removed line is held in the store exactly as long as it can be undone. A judgement: it
  removes a way to configure the two apart that nothing used.
- **The feed goes inside.** `ChangeFeed` stays a paradigm part with ports; the story mounts it with
  the page's `changes` topic and the facts its lines need (`[:stock]`), wires `feed.stock` to the
  lines, and sends the change on as `stock`. Kept at the page, the feed's placement and its wire to
  the lines would have stayed written twice, which is what this change removes; the clone check
  agreed (30 nodes with the feed on the pages). The cost: the portal's catalogue now gets stock
  through `draft.stock` after the lines have it (same order as before), and the cart, which shows
  stock only on its lines, has a clause that does nothing with it, since a page's `wire/3` must
  answer every output that fires (`grounded/0` only covers outputs that never fire there). The
  portal can't mount a second feed for its catalogue: one feed per topic per process (the hook id is
  the topic, and a second subscription would deliver each message twice).
- **Layers, not nesting.** A story that places stories is a layer above them (§2.2: "Abstraction
  layers replace hierarchical containment"). Left in the `:feature` layer it gave four R1 findings
  (`DraftOrder` calling `EditLines` and `UndoRemoval` as peers). `lint.exs` puts it in a
  `:shared_story` composition layer between the pages and the stories, matched by name. That layer
  holds one module today.
- **The trace goes inside.** `DraftOrder` routes its parts with `Steps.to`/`Steps.out` under its own
  name, and `test_helper.exs` checks it with the pages: every output of `EditLines`, `UndoRemoval`
  and the feed must route during the suite, as the pages' check did before the move, and its running
  drawing is `docs/diagrams/running/stories_draft_order.md`. On the pages' running drawings the
  inner hops are gone; a page now shows `draft` and what lands on the page.

The pages' `@parts` are one each (`draft`). The cart lost 12 lines, the portal 11; the story is 104.
What is still alike between the pages' `mount/3`: the `DraftOrder.mount` call itself, with the same
five keys (22 nodes at a 12-node threshold, under the default 26). That is placement and
configuration, which is what a page is for.

## What it costs

*Written before `DraftOrder`; the clone item is resolved above, and `lint.exs` gained one layer.*

- Production code is 5147 lines in `lib/`, from V52's 5644 (-497). The cart page grew from 333
  to 541 lines (479 non-blank, under the 500-line module limit), the portal from 217 to 303.
- The pages now hold logic: 25 R11 findings, against V52's 4. All are advisory. They are the shape
  the rule asks for: a `case` on what a call answers, a page function that patches when a step
  changes (`checkout/2`, `flow/2`), an assign read and passed to a call (`Checkout.start` with
  `@summary`), and five template calls (`SavedItems.count`, `Wishlist.count`, `Wishlist.ids`).
  *Since 2026-10-23* `lint.exs` passes `r11_calls: :wired_only`, which leaves out the hand-offs into
  called parts (the binding, the two assign reads and the five template calls): R11 reports 17, the
  8 branches, the gift-wrap arithmetic and 8 working chains.
  R11's share of application functions went from 5% to 14%, and the application layer is now 23%
  of functions, over the 20% the `app_share` ratio reports (never scored).
- One scored finding at `--strict` and `--super-strict` (gone since `DraftOrder`): `clone` (R7), 37 nodes alike in the two
  pages' `mount/3`. Both pages now end by mounting `UndoRemoval`, `EditLines` and `ChangeFeed` with
  the same configuration shape; in V52 other stories' mounts sat between them. It weighs 1 over 436
  functions and rounds to 100. It is real: the two pages also wire `EditLines` and `UndoRemoval` to
  each other with the same four clauses. A story holding both would remove it; that is a change to
  the variation points themselves and was left alone.
- No check was made advisory beyond V52's `r11`; `.credo.exs` is as in V52, and `lint.exs` is too
  but for the `:shared_story` layer `DraftOrder` added.
- The running drawing no longer shows pricing, checkout or the wishlist. Those are calls now, and a
  reader finds them in the page's clauses, not in the diagram.

## V52's design, kept (ALA Light on V51B)

Everything below is V52's note, unchanged. Where it names `PriceCart`, `PriceOrder`, `CheckOut`,
`SaveForLater`, `KeepWishlist`, `BrowseCatalog` or `SubmitOrder`, those stories are folded into
their pages in V53.

### What Light allows

V52 is V51B's code under the rule set of `ala_lab/docs/Q-ala-light-subsets.md`, subset 2: layers and
a composition page, with logic allowed on the page as pure functions. The full checklist stays.
What is relaxed: **R11 (composition only) is advice, not a score.** An application-specific pure
function may be written on a page or in a story and handed to a part as configuration, or called
from a `wire/3` clause; a branch or loop that would otherwise become a one-use abstraction may stay
on the page. R7 (earns its existence) then decides whether a single-use abstraction is a finding.
The public-surface limit is reported only (the linter's default), and R10 reads lifecycle by
identity key as the identity's business (the checklist's reading). What is still asked: the wiring
reads top to bottom (R8), literals live at the composition (R3), a domain part never knows one
page's words (R3, R6), and the page does not compute between `wire/3` clauses with assigns used as
scratch. Spray's basis is §6.28.1 and §6.28.3: an application-specific function kept in the
application layer, because "all the code in the application is specific to the application
requirements".

The only baseline changes from V51B are the folds (the portal's volume tier, the cart's gift-wrap
cost and promo validation, each now a function on its page) and `lint.exs` passing
`checks: %{r11: :advisory}`. The shape below is V51B's, unchanged; the difference is meant to show
during changes, when a rule may be written on the page instead of as a component.

### V51B's design, kept

V51's design with one editing story placed by both pages, the subject of V51B and described last
below, after the running trace, which was first built in V51B (then called V52, a retired name; this
V52 is a different variant) and has since been added to V50 and V51 in place. The trace sections are kept as the record of that build. V51 draws a page by
parsing its own source for `wire/3` clauses, which can drift (a clause the parser misreads draws
wrong and nothing notices). Spray's instruction is to draw the diagram from the code that runs, and
the checklist's R8 technique is a coverage test over the built graph. In Elixir the graph isn't built
once; it runs clause by clause. So V51B records it while it runs.

## How it records

- `Steps.to(socket, page, parts, key, port, payload, out)` is what a page's `to/4` calls: it records
  a hop from whatever output is being routed (or `:outside`, for a browser event, a timer or a
  PubSub message) to `{key, port}`, then sends the story its input.
- `Steps.out(socket, page, key, output, wire)` is what a page's `out/1` builds: it marks the output
  as the hop being routed, runs the page's `wire/3` clause, and if the clause sent it to no story,
  records that it landed on the page.
- `Trace` is an ETS table the test helper turns on; `Trace.hop/3` is a no-op without it, so the
  pages pay nothing in production.

The pages changed two lines each (`to/4` and `out/1`); the stories didn't change. Which output is
being routed lives in the process dictionary of the LiveView process for the length of one clause,
restored after, so nested routing (a story's output sent to a story whose output lands on the page)
records each hop correctly.

## What the first run found

`ExUnit.after_suite` writes `docs/diagrams/running/*.md` and reports every declared output no hop
left from. The first run reported two: the cart page's `ui: :tab` (no test switched a tab) and the
portal's `undo: :expired` (no portal test let the undo window close). Both were wired and both were
untested; the source-parsed check saw a clause and was satisfied. V51B adds the two tests.

## What it costs

- Two lines per page, and a process-dictionary read per hop: no measurable cost, and nothing in
  production when the table is off.
- The drawing shows what the suite exercised, not what the source says: an output no test routes
  disappears from the picture and appears in the report instead. That is the point, and it is also
  why the source-parsed `Drawing` stays for a story's inside, which the trace doesn't enter.
- Edges to `:outside` and `:page` are labelled by port only; what landed where on the page (an
  assign, a flash, a stream) is the clause's business and the source drawing still shows it as a
  dotted arrow.

## One editing story, two pages (2026-10-11)

V51 shared `UndoRemoval` between the cart and the portal and kept two editing stories, `EditCart`
(three parts: lines, promo, totals) and `EditOrder` (one part, `OrderLines`, which priced itself by
volume tier). The duplication was in the state layer as much as the story layer: two line
abstractions that both hold lines, change quantities and hand a removed line to undo. Now:

- **`EditLines`** is the one editing story. Its part is `CartLines`, which gained an absolute
  quantity (`update_quantity` with `quantity:` beside `delta:`) and a line arriving at a quantity
  (`receive` with `{item, quantity}`), both as clauses of functions it already had, so its public
  surface stays at twelve. Its events are the union of both pages' line events; its inputs are
  `receive`, `add_product`, `add`, `confirm_removal`, `stock` and `request_checkout`; its outputs are
  `contents`, `removed`, `saved`, `line` and `checkout_requested`.
- **The row is the page's.** `EditLines.rows` takes the page's row component as `row` (a function of
  assigns) and whatever that row needs beyond the row itself as `row_attrs`; the story renders each
  row through it, passing the event names it owns (`on_quantity="update_quantity"` and the rest).
  The story owns its events, as V51's R5 finding requires; the page owns what a line looks like,
  as the checklist's UI-layout note (§7.14) puts it. `order_line_row` takes `on_set_quantity` now.
- **Pricing is the page's story.** `PriceCart` holds `Promo` and `CartTotals` (shipping choice, promo,
  gift wrap, checkout starting); `PriceOrder` holds the new `OrderTotals` (volume tiers, review).
  Each takes `contents` in and sends `summary` out, so the page wires one hop, `edit_lines.contents
  → price.contents`, that V51 kept inside `EditCart`.
- **Grounded outputs.** The portal's rows offer no save, wishlist or checkout, so three of
  `EditLines`' outputs can never fire there. The page says so in `grounded/0`; `Wiring.gaps/1`
  subtracts them and so does `Trace.unrouted/1`, so the suite still fails on any other output that
  never routed.

The portal page's wiring reads: edit the lines, price them, undo, browse, submit. The cart page's:
edit the lines, price them, undo, save, wishlist, check out. The two pages' `mount` differ in the
row, the stream name, the pricing story and the undo window. Neither story knows which page it is on.

Found while scoring with a layer map, and fixed: the trace kept "which output is being routed" in
the process dictionary. The linter's R4 check calls that hidden state, and it is right that nothing
in the socket said so. The marker now rides in `socket.private` for the length of one clause and is
restored on the way out, which is the same nesting the process dictionary gave, in the thing the
paradigm already threads. `lint.exs` holds the layer map so the score is reproducible.

### What it costs

- One more hop per line change on each page (`contents` to the pricing story), visible in the
  running drawing. V51 had it inside one story.
- A story that renders the page's row through a function it is handed: one indirection a reader
  meets once, in `line_row/1`.
- The cart page grew by thirty lines (two stories' events and wires where there was one); the
  portal by none; `lib/` shrank by 250 non-blank lines with `EditOrder` and `OrderLines` gone.
- `PriceOrder.mount/3` assigns a built `OrderTotals` to the socket. Until 2026-10-19 the linter read
  that as a pass-through and left R7 unmet from `--strict`; it now reads an `assign` of a built
  value as building state, as it already read a struct update.

## Outside change as a part (2026-10-21)

Each page used to subscribe through an `on_mount` hook (`Subscribed`) to `Foundation.Broadcast`'s
topic and route what came in by hand: a `handle_info` clause per message kind, building the stories'
`%{product_id, stock}` change itself, and two clauses on each page to ignore catalogue edits. The
fact format lived in three places and a new kind of change meant a clause on every page.

- **`Paradigms.ChangeFeed`** is the paradigm, in the programming-paradigms layer. A page mounts it like a
  story, `ChangeFeed.mount(socket, [topic:, facts:], out(:feed))`, lists it in `@parts` as `feed`, and
  wires its outputs (`product`, `stock`) with `wire/3` clauses. It subscribes once connected and
  attaches one `handle_info` hook that sends each fact the page asked for through the page's `out`,
  so the trace records `feed → edit_lines` as it does any other hop.
- **Publishing** is `ChangeFeed.publish(opts, product)`, configured the same way, which the page that
  makes the change calls: the cart hands it to `SettleOrder` as `announce`; the product pages call
  it on `saved`. `SaveProduct` only saves now.
- **Facts** are built in one place, `ChangeFeed.facts/1`: the product itself, and `%{product_id, stock}`.
  The topic is `Catalog.changes_topic/0`, so publisher and subscriber share it and the id.
- The cart and portal ask only for `:stock` and ground `feed: :product` in `grounded/0`; that names
  the kind twice (in the config and in `grounded`), and nothing checks that the two agree.

Found by the move: a stock edit at /products reached the product list but no cart or portal, which
ignored `:product_updated`. With the feed it was one word, `:stock` in the product pages' publish
config; a test edits stock at /products/:id/show/edit and sees an open cart say "Out of stock".
Still not live: a price, name or new product on an open cart or portal (no input takes them), and a
deleted product anywhere (nothing publishes it).
