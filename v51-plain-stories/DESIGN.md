# V51 design: plain stories

A Phoenix LiveView design with Spray's Features layer, built from plain functions. Each page composes
a few **story modules**, one per user story. A story instantiates and configures its own stateful
domain abstractions, wires them to each other, handles the browser events its own view fires, and
lays out that view from generic UI components. The page wires stories to each other with one `wire/3`
clause per story output. Everything runs on a two-function runner, with no story struct, runner or
behaviour of its own. It meets the full [ALA Checklist](https://github.com/modellurgist/ala_checklist),
including every rule `ala_lint` checks at its strictest tier.

Use it when a page is at or past about 500 lines (Spray's size limit, where he adds a Features layer),
or will grow. For a smaller page, V50 is the same design without stories, and simpler.

## At a glance

| | |
|---|---|
| Composition layers | the page (application) and stories (Features) |
| Wiring form | inside a story, one private `wire/4` clause per port of its parts; on the page, one `wire/3` clause per story output |
| Where state lives | the page's assigns, one key per part (`lines`, `promo`, `totals`, `undo`, ...) |
| Runner | `Steps.run/4` and `Steps.feed/6`, shared by pages and stories |
| How a story sends | through an `out` function the page gives it: the page's `wire/3` with the story's key bound |
| Browser events | each story declares `events/0` and handles them in `handle_event/4`; the page dispatches by the declared list |
| Timer and task names | chosen by the page and passed into the story's `mount` |
| Checks | `Wiring.gaps/1` for pages and stories, `input_gaps/1`, `event_gaps/1`, no event claimed by two stories |
| Diagram | `Drawing.mermaid/1` for a page, `Drawing.mermaid_story/1` for one story's inside |
| Message hops between components | none |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `GoodDealWeb.*Live.*`, `GoodDealWeb.CartSession`, `GoodDealWeb.CheckoutMetadata`, `GoodDeal.Catalog` | pages: configuration, story mounts, event dispatch, `wire/3` between stories, templates; store-wide words and calibration |
| Features | `GoodDealWeb.Stories.*` | story modules: `EditCart`, `UndoRemoval`, `SaveForLater`, `KeepWishlist`, `CheckOut` (cart page); `EditOrder`, `BrowseCatalog`, `SubmitOrder` and `UndoRemoval` (portal) |
| State | `GoodDeal.State.*` | stateful domain abstractions with declared ports: `CartLines`, `Promo`, `CartTotals`, `Undo`, `SavedItems`, `Wishlist`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit`, `RecordEdit`, `PageUI` |
| Domain | `GoodDeal.Domain.*`, `GoodDeal.Actions.*`, `GoodDeal.Lines` | product-free rules and configured store-work instances: pricing functions, `StockStatus`, `AddLine`, `Charge`, `SettleOrder`, `PlaceOrder`; the product facts that travel live (`ProductFacts`); plain functions over a list of stored lines |
| Programming paradigms and foundation | `GoodDealWeb.Paradigms.*`, `GoodDeal.Paradigms.*`, `GoodDeal.Components.*`, `GoodDeal.Foundation.*` | the runner (`Steps`), wiring checks, drawer, change feed (`ChangeFeed`), step machine (`Transitions`), generic UI components, stores, payment gateway |

Both the Application and Features layers are composition layers: they instantiate, configure and
wire, and hold no `if`, `case` on data, or arithmetic. In the linter's layer map, the Features layer is
named `:feature`, which makes it a composition layer for the R11 checks.

## Building block 1: a state module with ports

The same contract as V50. A module of pure functions over its own struct; each input is
`input(state, payload) -> {new_state, [port: payload]}`; `ports/0` declares inputs and outputs. Outputs
announce facts and never name a destination; configuration comes in once through `new/1`; there's no
I/O and no call to a peer.

The cart is split into small state abstractions so each names one concept and keeps a small public
surface:

| Module | Holds | Inputs | Outputs |
|---|---|---|---|
| `CartLines` | the cart's id, its stored lines, which are gift-wrapped | load, update_quantity, remove, save_for_later, receive, confirm_removal, line, toggle_gift_wrap, set_stock, request_checkout | rows, contents, removed, saved, line, changed, checkout_requested |
| `Promo` | the applied code and its percentage | enter | discount, applied, rejected |
| `CartTotals` | the last contents, discount and shipping method it received, and the pricing rules | contents, discount, select_shipping, start_checkout | summary, checkout_started |

`CartLines.contents` carries only what pricing reads: each line's quantity and product amount, and the
wrapped count. Checkout receives `{cart_id, items}`, never a cart.

## Building block 2: a story module

A story is a module of plain functions with a small, fixed public surface:

| Function | What it is |
|---|---|
| `parts/0` | `%{part_key => StateModule}`, the state it instantiates |
| `events/0` | the browser events its own view fires |
| `ports/0` | `%{in: [...], out: [...]}`, the story's own input and output ports |
| `mount(socket, opts, out)` | assigns its parts, configured instances and streams; loads what it needs |
| `input(socket, port, payload, out)` | one clause per input port |
| `handle_event(name, params, socket, out)` | one clause per event in `events/0`, decoding params at the edge |
| view functions | function components (`rows/1`, `totals/1`, `view/1`) taking explicit attributes |

Everything else is private, including `wire/4`, the story's inner wiring: one clause per port of each
part.

```elixir
defmodule GoodDealWeb.Stories.UndoRemoval do
  use GoodDealWeb, :html
  alias GoodDeal.State.Undo
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{undo: Undo}
  def events, do: ~w(undo_remove)

  def ports,
    do: %{in: [capture: :item, expire: :item], out: [restored: :item, expired: :item_id, pending: :flag]}

  def mount(s, opts, _out),
    do: assign(s, undo: Undo.new([]), undo_timer: {opts[:timer], opts[:window_ms]})

  def handle_event("undo_remove", _params, s, out), do: run(s, &Undo.restore(&1, nil), out)

  def input(s, :capture, item, out), do: run(s, &Undo.capture(&1, item), out)
  def input(s, :expire, item, out), do: run(s, &Undo.expire(&1, item.id), out)

  defp run(s, step, out), do: Steps.run(s, :undo, step, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :undo, {:captured, item}, out) do
    {timer, window_ms} = s.assigns.undo_timer
    s |> Steps.start_timer(timer, item, window_ms) |> out.({:pending, true})
  end

  defp wire(s, :undo, {:restored, item}, out) do
    {timer, _} = s.assigns.undo_timer
    s |> Steps.stop_timer(timer) |> out.({:pending, false}) |> out.({:restored, item})
  end

  defp wire(s, :undo, {:expired, item_id}, out),
    do: s |> out.({:pending, false}) |> out.({:expired, item_id})

  def view(assigns), do: ~H"<.notice shown={@pending} text={@t.text} action={@t.undo} event=\"undo_remove\" />"
end
```

The rules a story follows:

- **It sends outputs only through `out`**, `out.(socket, {port, payload})`. It never knows its own key,
  the page, or any other story.
- **It owns its parts, configured instances and streams.** Every value the page renders or passes on
  leaves through an output port, and the page assigns it. A story never sets an assign the page's
  template reads.
- **It owns its events.** The names its view fires appear in its template, its `events/0` and its
  `handle_event/4` heads, all in one module.
- **It takes names the page chooses** for anything the page must also match: the timer name and the
  task name come in through `mount` options.
- **It builds no app-level instance.** Instances whose configuration comes from application modules
  (`Charge` uses `CheckoutMetadata`; the line-item builder uses `Catalog`) are built by the page and
  passed in.
- **Feature-specific details live in the story**: its flows, step paths, flash words, validation
  messages.

A story with several parts wires them to each other in `wire/4`. `EditCart` runs `CartLines`, `Promo`
and `CartTotals`, and its clauses feed the lines' `contents` and the promo's `discount` into the totals:

```elixir
defp wire(s, :lines, {:contents, contents}, out),
  do: run(s, :totals, &CartTotals.contents(&1, contents), out)

defp wire(s, :promo, {:discount, discount}, out),
  do: run(s, :totals, &CartTotals.discount(&1, discount), out)

defp wire(s, :totals, {:summary, summary}, out), do: out.(s, {:summary, summary})
```

## Wiring: the page

```elixir
@parts %{edit_cart: EditCart, undo: UndoRemoval, saved: SaveForLater, wishlist: KeepWishlist,
         check_out: CheckOut, ui: PageUI}
def parts, do: @parts

def mount(_params, session, socket) do
  cart_id = CartSession.fetch(session)
  pricing = %{shipping: ..., stock_status: ..., promo: ..., gift_wrap: ...}
  payment = [line_items: ..., charge: %Charge{...}, settle: %SettleOrder{...}]

  {:ok,
   socket
   |> assign(texts: texts(), ui: PageUI.new(tabs: [:items, :saved, :wishlist]), summary: ..., ...)
   |> UndoRemoval.mount([timer: :undo, window_ms: Catalog.undo_window_ms()], out(:undo))
   |> SaveForLater.mount([cart_id: cart_id], out(:saved))
   |> KeepWishlist.mount([], out(:wishlist))
   |> EditCart.mount([cart_id: cart_id, pricing: pricing, hold_ms: Catalog.undo_window_ms()], out(:edit_cart))
   |> CheckOut.mount([task: :payment] ++ payment, out(:check_out))}
end

@edit_cart_events EditCart.events()

# each story handles the events its own view fires
def handle_event(event, params, socket) when event in @edit_cart_events,
  do: {:noreply, EditCart.handle_event(event, params, socket, out(:edit_cart))}
# ... one such clause per story, plus page-level events such as "switch_tab"

def handle_info({:timer, :undo, item}, socket), do: {:noreply, to(socket, :undo, :expire, item)}
def handle_async(:payment, {:ok, {:ok, reference}}, socket),
  do: {:noreply, to(socket, :check_out, :succeeded, reference)}

defp to(socket, key, port, payload), do: @parts[key].input(socket, port, payload, out(key))
defp out(key), do: &wire(&1, key, &2)

# {story, port} → where it wires on this page
defp wire(s, :edit_cart, {:summary, summary}), do: assign(s, :summary, summary)
defp wire(s, :edit_cart, {:removed, item}), do: to(s, :undo, :capture, item)
defp wire(s, :undo, {:restored, item}),
  do: s |> to(:edit_cart, :receive, item) |> put_flash(:info, "Item restored")
defp wire(s, :wishlist, {:taken, product}),
  do: s |> to(:edit_cart, :add_product, product) |> put_flash(:info, "Added to cart")
defp wire(s, :check_out, {:pay_requested, _}), do: to(s, :edit_cart, :request_checkout, nil)
```

The template places each story's view components and passes them the assigns the page set from
story outputs:

```heex
<EditCart.rows streams={@streams} summary={@summary} wishlist_ids={@wishlist_ids} t={@texts.cart} />
<EditCart.totals summary={@summary} promo_error={@promo_error} t={@texts.cart} />
```

A page may also run a state module directly, as V50 does, when it isn't worth a story (`PageUI` for
the tabs, `RecordEdit` on the product pages).

## Runtime

The same runner as V50: `Steps.run/4` steps a part and folds each output through a wire function;
`Steps.feed/6` runs an input on what a function answers. A story calls it with its own `wire/4`
closed over `out`; the page calls it with `wire/3`. Every effect runs in the page's process, in the
same handler call, in output order.

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** owned by the story whose view fires them (`handle_event/4`). The page has one
  dispatch clause per story, guarded by a module attribute built from `events/0`.
- **URL steps:** `CheckOut` and `SubmitOrder` own their flows, URL edges and step paths, and patch the
  URL themselves when their state machine changes step. The page's `handle_params/3` looks the URL
  segment up in its own table and sends it to the story's `goto` input.
- **Timers and tasks:** a story starts them under names the page passed in; the page's `handle_info`
  and `handle_async` clauses use the same names, so only the page knows the two agree.
- **Store I/O:** reads are `feed` with a function capture; writes are outputs a story wires to a store
  call (`Carts.apply_change/1`); multi-step work is a configured domain instance.
- **Change made elsewhere:** a change feed part, `ChangeFeed` (below), so the page's wiring shows it.

## ChangeFeed: change made elsewhere

A page shows another session's purchase or a staff edit through one part of the programming
paradigms layer. `%ChangeFeed{topic, format, facts}` is both ends: `ChangeFeed.mount/3` subscribes the page and
sends each fact of a kind in `facts` through the `out` the page gives it, the same `out(:feed)` a
story gets; `ChangeFeed.publish/2` sends a changed record as the facts its `format` builds. The format,
`ProductFacts`, declares the ports (`stock: {product_id, stock}`, `product: the saved record`), so
`@parts` names it under the page's `feed` key and the usual gap check and trace cover it. A page
grounds the kinds it doesn't take.

```elixir
feed = %ChangeFeed{topic: Catalog.product_topic(), format: ProductFacts, facts: [:stock]}
socket |> ... |> ChangeFeed.mount(feed, out(:feed))           # cart and portal subscribe
settle: %SettleOrder{announce: &ChangeFeed.publish(feed, &1), ...}   # the cart's purchase publishes

defp wire(s, :feed, {:stock, change}), do: to(s, :edit_cart, :stock, change)          # cart
defp wire(s, :feed, {:stock, change}),
  do: s |> to(:order, :stock, change) |> to(:catalog, :stock, change)                 # portal
```

The product pages publish `[:product, :stock]` from their save wire, and the list subscribes to both.
Delivery is one `handle_info` hook (`attach_hook/4`) the part attaches; it takes its own topic's
messages and passes every other message on, so the page writes no clause per kind of change.

## Checks

- `Wiring.gaps(module)` compares a page's `wire/3` heads, or a story's `wire/4` heads, with every output
  port its parts declare, both ways.
- `Wiring.input_gaps(story)` compares a story's `input/4` heads with its declared input ports.
- `Wiring.event_gaps(story)` compares the events its templates fire, its `events/0`, and its
  `handle_event/4` heads.
- A test checks that no two stories on a page declare the same event.
- `Drawing.mermaid/1` draws a page's links between stories; `Drawing.mermaid_story/1` draws one story's
  events, inputs, inner wires and outputs.
- `ala_lint` with the Features layer mapped checks R11 on stories as well as pages, counts
  `out.(socket, {port, payload})` as a story's sent output, and pairs event and timer names across
  modules (R5).

## Applying it to another project

1. Start from the V50 design for one page. When the page grows past the size limit, list its user
   stories.
2. Split state that mixes concepts into small state modules, so each story's parts name one concept.
3. For each story, write a module with `parts/0`, `events/0`, `ports/0`, `mount/3`, `input/4`,
   `handle_event/4`, private `wire/4` clauses and its view components. Send outputs only through `out`.
4. Move each event handler from the page into the story whose view fires it.
5. Rewrite the page: `parts/0`; mount each story with its configuration and `out(key)`; one event
   dispatch clause per story; `wire/3` clauses for the links between stories and for landing story
   outputs as assigns.
6. Name timers and tasks on the page and pass the names in. Build app-level instances on the page.
7. Add the coverage tests (`gaps`, `input_gaps`, `event_gaps`, event clashes) for every page and story.
8. Map a Features layer in `ala_lint` and fix what it reports.

## Trade-offs and limits

- A story is a new kind of module to learn, though everything in it is plain functions and clauses.
- Stories share the page's assigns. Two stories using the same part key would overwrite each other,
  and nothing checks for that yet.
- The story shape is a convention the `Wiring` tests check, not a `@behaviour` the compiler checks.
- A cross-story request takes a longer path: Pay is in the checkout's view, so `CheckOut` sends
  `pay_requested` out, the page sends it to `EditCart`, and the lines come back through the page.
- `CartTotals` keeps the last value of each input it joins; it can only go stale if a wire is missing.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/good_deal_web/live/cart_live/show.ex` | a page composing five stories |
| `lib/good_deal_web/stories/edit_cart.ex` | a story wiring three state parts together |
| `lib/good_deal_web/stories/undo_removal.ex` | a small story shared by two pages |
| `lib/good_deal_web/stories/check_out.ex` | a story with a flow, URL paths, a task and page-built instances |
| `lib/good_deal/state/cart_lines.ex`, `promo.ex`, `cart_totals.ex` | the split cart state |
| `lib/good_deal_web/paradigms/steps.ex`, `wiring.ex`, `drawing.ex` | runner, checks, drawer |
| `lib/good_deal_web/paradigms/change_feed.ex`, `lib/good_deal/domain/product_facts.ex` | change feed and the facts it carries |
| `test/good_deal_web/live/wiring_test.exs` | the coverage, event and diagram tests |

## The wiring as it ran (2026-10-16)

The trace first built as V51B is now part of V51: `Steps.to/7` records a hop from whatever output is
being routed (or `:outside`) to `{key, port}` and sends the story its input; `Steps.out/5` marks an
output as the hop being routed, runs the page's `wire/3` clause, and records a landing when the
clause sent it to no story. The marker rides in the socket's private map for the length of one
clause. The pages changed two lines each (`to/4` and `out/1`), plus a one-line wrapper on the cart
page so the tab state it runs itself routes through `out/1` like a story's; the stories did not
change. `Trace` is an ETS table the test helper turns on; off, the pages pay nothing.

The first run reported two declared outputs no test routed, the cart's `ui: :tab` and the portal's
`undo: :expired`, both wired, both untested, both now tested.

## Later (2026-10-21): change feed

The pages' `handle_info` clauses for `stock_changed`, `product_created` and `product_updated` and the
`on_mount` hook `Subscribed` became the `ChangeFeed` part above; `Foundation.Broadcast` and the broadcasts
inside `SaveProduct` went with them, and the save's publishing moved to the page that wires the save.
The running diagrams now draw `feed -->|"stock → stock"| edit_cart` where they drew an arrow from
outside. Moving it closed a gap: a staff stock edit at /products reached only the product lists.
Not closed, and not a one-line wire: a new product doesn't appear in an open portal catalogue, and
a price edit doesn't reach an open cart; each needs an input port on the state that holds the rows.
