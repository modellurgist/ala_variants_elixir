# V52 design: the wiring as it ran, and one editing story for two pages

V51's design plus one paradigm, a trace of the hops the pages route, and (a day later, built into
this variant rather than a V53) one editing story placed by both pages. The trace first. V51 draws a page by
parsing its own source for `wire/3` clauses, which can drift (a clause the parser misreads draws
wrong and nothing notices). Spray's instruction is to draw the diagram from the code that runs, and
the checklist's R8 technique is a coverage test over the built graph. In Elixir the graph isn't built
once; it runs clause by clause. So V52 records it while it runs.

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
untested; the source-parsed check saw a clause and was satisfied. V52 adds the two tests.

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
- `PriceOrder.mount/3` is a one-line pass-through to `OrderTotals.new/1`, reported (not scored) by
  the linter; it is the story's own interface and stays.
