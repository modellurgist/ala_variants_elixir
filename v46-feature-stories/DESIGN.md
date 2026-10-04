# V46 design: feature stories

A Phoenix LiveView design with Spray's Features layer. Each page composes **stories**, one per user
story. A story is a Features-layer module that instantiates and configures its own stateful domain
abstractions ("parts"), wires them with one `wire/4` clause per part port, handles the browser events
its own view fires, keeps its own view values, and declares ports for the few links that leave it.
The page wires stories to each other with one `wire/3` clause per story output. A small paradigm
module, `Story`, runs stories: it holds each one as a `%Story{}` value in the page's assigns, steps
its parts, follows its inner wiring, and hands what it sends out to the page. It meets the full
[ALA Checklist](https://github.com/modellurgist/ala_checklist).

Use it when a page is at or past about 500 lines, Spray's size limit where he adds a Features layer.
V51 makes the same split with plain functions and no story runtime; V47 makes it with typed bindings
maps.

## At a glance

| | |
|---|---|
| Composition layers | the page (application) and stories (Features) |
| Wiring form | inside a story, one `wire(socket, me, part, {port, payload})` clause per part port; on the page, one `wire/3` clause per story output |
| Where state lives | one `%Story{}` per story in the page's assigns: its parts, configured instances, timers and view values |
| Runtime | `Story` (runs a story's parts, sends outputs to the page, timers, tasks, event dispatch), `Sinks` (landing points), `Steps` (for page-level state) |
| Browser events | one generic `handle_event/3`; `Story.event/4` finds the story whose `events/0` lists the name |
| Timers and tasks | report to the story's own input ports, through one generic `handle_info` and one generic `handle_async` |
| Checks | `Wiring.gaps/1` (page), `Wiring.story_gaps/1` (each story), `Wiring.event_clashes/1` |
| Diagram | `Drawing.mermaid/1` (page) and `Drawing.mermaid_story/1` (one story) |
| Message hops between components | none |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `GoodDealWeb.*Live.*`, `GoodDealWeb.CartSession`, `GoodDealWeb.CheckoutMetadata`, `GoodDeal.Catalog` | pages: configuration, stories built and mounted, `wire/3` between stories, templates placing story views |
| Features | `GoodDealWeb.Stories.*` | `EditCart`, `UndoRemoval`, `SaveForLater`, `KeepWishlist`, `CheckOut` (cart page); `EditOrder`, `BrowseCatalog`, `SubmitOrder`, `UndoRemoval` (portal) |
| State | `GoodDeal.State.*` | stateful domain abstractions with declared ports: `Cart`, `Undo`, `SavedItems`, `Wishlist`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit`, `RecordEdit`, `PageUI` |
| Domain | `GoodDeal.Domain.*`, `GoodDeal.Actions.*`, `GoodDeal.Cart`, `GoodDeal.Lines` | pricing and rule functions, configured store-work instances (`AddLine`, `Charge`, `SettleOrder`, `PlaceOrder`), the storefront cart aggregate, and plain functions over a list of stored lines shared by cart and portal |
| Programming paradigms and foundation | `GoodDealWeb.Paradigms.*`, `GoodDeal.Paradigms.*`, `GoodDeal.Components.*`, `GoodDeal.Foundation.*` | `Story`, `Sinks`, `Steps`, `Wiring`, `Drawing`, the `on_mount` subscription hook, the state-machine table, generic UI components, stores, PubSub wrapper |

Application and Features are both composition layers: no `if`, `case` on data or arithmetic, only
instances, configuration and wiring. Map the Features layer as `:feature` in the linter so R11 applies.

## Building block 1: a state module with ports

A module of pure functions over its own struct. Each input is `input(state, payload) -> {new_state,
[port: payload]}`; `ports/0` declares inputs and outputs. Outputs announce facts; configuration comes
in once; no I/O; no peer calls; a consumer gets only the data it needs (checkout gets `{cart_id,
items}`). This contract is the same in every clause-wired variant.

## Building block 2: a story

A story module implements the `GoodDealWeb.Paradigms.Story` behaviour:

| Callback | What it is |
|---|---|
| `parts/0` | `%{part => StateModule}` |
| `ports/0` | the story's own `%{in: [...], out: [...]}` |
| `events/0` | the browser events its view emits |
| `streams/0` | the LiveView streams its view shows |
| `new(opts)` | builds a `%Story{}`: parts, configured instances, timers `%{name => {ms, input_port}}`, starting view values |
| `input(socket, me, port, payload)` | one clause per input port |
| `event(socket, me, name, params)` | one clause per event, decoding params |
| `wire(socket, me, part, {port, payload})` | one clause per part port: the story's inner wiring |
| view functions | function components that take `story={@key}` and read `@story.view` |

`me` is the story's key on the page, passed in by the runner, so a story never hard-codes it.

```elixir
defmodule GoodDealWeb.Stories.UndoRemoval do
  use GoodDealWeb, :html
  @behaviour GoodDealWeb.Paradigms.Story
  alias GoodDeal.State.Undo
  alias GoodDealWeb.Paradigms.{Sinks, Story}

  def parts, do: %{undo: Undo}
  def streams, do: []
  def events, do: ["undo_remove"]
  def ports, do: %{in: [capture: :item, expire: :item], out: [restored: :item, expired: :item_id]}

  def new(opts),
    do:
      Story.new(__MODULE__, %{undo: Undo.new([])},
        timers: %{undo: {Keyword.fetch!(opts, :window_ms), :expire}},
        view: [pending: false]
      )

  def input(s, me, :capture, item), do: Story.run(s, me, :undo, &Undo.capture(&1, item))
  def input(s, me, :expire, item), do: Story.run(s, me, :undo, &Undo.expire(&1, item))
  def event(s, me, "undo_remove", _), do: Story.run(s, me, :undo, &Undo.restore(&1, nil))

  def wire(s, me, :undo, {:captured, item}),
    do: s |> Story.show(me, :pending, true) |> Story.start_timer(me, :undo, item)

  def wire(s, me, :undo, {:restored, item}),
    do: s |> Sinks.stop_timer(:undo) |> Story.show(me, :pending, false) |> Story.send_out(me, :restored, item)

  def wire(s, me, :undo, {:expired, item_id}),
    do: s |> Story.show(me, :pending, false) |> Story.send_out(me, :expired, item_id)

  def view(assigns),
    do: ~H"<.notice shown={@story.view.pending} text={@t.text} action={@t.undo} event=\"undo_remove\" />"
end
```

What a story's `wire/4` clauses use: `Story.run/4` and `Story.feed/6` (step a part), `Story.show/4`
(set a view value), `Story.send_out/4` (send a story output to the page), `Story.call/4` and
`Story.async/5` (configured instances, by name), `Story.start_timer/4`, and `Sinks` landing points
(`stream_change`, `patch`, `stop_timer`).

## Wiring: the page

```elixir
def mount(_params, session, socket) do
  cart_id = CartSession.fetch(session)
  pricing = %{shipping: ..., stock_status: ..., promo: ..., gift_wrap: ...}

  stories = %{
    edit_cart: EditCart.new(cart_id: cart_id, pricing: pricing),
    undo: UndoRemoval.new(window_ms: Catalog.undo_window_ms()),
    saved: SaveForLater.new(),
    wishlist: KeepWishlist.new(add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id}),
    check_out: CheckOut.new(checkout: [flow: @checkout_flow, ...], charge: %Charge{...}, settle: %SettleOrder{...})
  }

  {:ok,
   socket
   |> assign(texts: texts(), ui: PageUI.new(tabs: [:items, :saved, :wishlist]), summary: nil, ...)
   |> Story.mount(stories, &wire/3)
   |> Story.input(:edit_cart, :mounted, cart_id)
   |> Story.input(:check_out, :mounted, nil)}
end

def handle_event(name, params, socket), do: {:noreply, Story.event(socket, @stories, name, params)}
def handle_async({:story_async, _, _, _} = task, result, socket),
  do: {:noreply, Story.async_result(socket, task, result)}
def handle_info({:story_input, key, port, payload}, socket),
  do: {:noreply, Story.input(socket, key, port, payload)}

# {story, port} → where it wires on this page
defp wire(s, :edit_cart, {:summary, summary}),
  do: s |> assign(:summary, summary) |> Story.input(:check_out, :summary, summary)
defp wire(s, :edit_cart, {:removed, item}), do: Story.input(s, :undo, :capture, item)
defp wire(s, :undo, {:restored, item}),
  do: s |> Story.input(:edit_cart, :receive, item) |> put_flash(:info, "Item restored")
```

The template places each story's view, passing the story value: `<UndoRemoval.view story={@undo}
t={@texts.undo} />`. Page-level state that isn't worth a story (`PageUI`) runs through `Steps.run/4` as
in V48.

## Runtime: `Story`

```elixir
def run(socket, key, part, step) do
  story = socket.assigns[key]
  {state, outputs} = step.(story.parts[part])
  socket = assign(socket, key, %{story | parts: Map.put(story.parts, part, state)})
  Enum.reduce(outputs, socket, &story.module.wire(&2, key, part, &1))
end

def send_out(socket, key, port, payload), do: socket.assigns.page_wire.(socket, key, {port, payload})

def event(socket, keys, name, params) do
  case Enum.find(keys, &(name in socket.assigns[&1].module.events())) do
    nil -> raise ArgumentError, "no story on this page handles the event #{inspect(name)}"
    key -> socket.assigns[key].module.event(socket, key, name, params)
  end
end
```

`Story.mount/3` assigns each story and its streams, and stores the page's `wire/3` as `page_wire`, which
`send_out` calls. A timer started with `Story.start_timer/4` sends `{:story_input, key, port, payload}`
to the page after its configured delay; a task started with `Story.async/5` is named
`{:story_async, key, ok, error}`, and `async_result/3` delivers its outcome to the story's `ok` or
`error` input. So the page knows no timer or task name.

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** owned by stories; one generic page clause dispatches by `events/0`.
- **URL steps:** `CheckOut` and `SubmitOrder` own their flows (a `{from, event, to}` table) and step
  paths; the page's `handle_params/3` sends the URL's step to the story's `goto` input.
- **Store I/O:** reads through `Story.feed` with a function or a named instance; writes are outputs a
  story wires to a store call; multi-step work is a configured domain instance kept in the story.
- **PubSub:** an `on_mount` hook subscribes; `handle_info` sends each fact to a story input.

## Checks

- `Wiring.gaps(page)` compares the page's `wire/3` heads with every output its stories declare.
- `Wiring.story_gaps(story)` checks one story's `wire/4` heads against its parts' ports, its `input/4`
  heads against its input ports, and its `event/4` heads against `events/0`.
- `Wiring.event_clashes(page)` lists events claimed by two stories on a page.
- `Drawing.mermaid/1` and `Drawing.mermaid_story/1` draw the page and one story from their clauses.

## Applying it to another project

1. Start from a V48-style page. When it outgrows the size limit, list its user stories.
2. Copy the `Story` and `Sinks` paradigm modules and the behaviour.
3. For each story, write the callbacks above: parts, ports, events, streams, `new/1`, `input/4`,
   `event/4`, `wire/4` and view components. Send outputs only with `Story.send_out/4`.
4. Rewrite the page: build the stories in `mount/3`, `Story.mount/3` them with `&wire/3`, add the three
   generic clauses (event, timer, async), and write `wire/3` for the links between stories.
5. Add `gaps`, `story_gaps` and `event_clashes` tests, and map the Features layer in the linter.

## Trade-offs and limits

- Familiarity drops a point against V48: a story has four kinds of clause, a behaviour, a struct and
  a runner to learn.
- About 600 more lines than V48, mostly the eight stories and the 145-line runner.
- `Story` itself has a public surface just over the strictest lint tier's limit, and the storefront
  `Cart` state module is wide; V51 splits the cart and drops the runner.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/good_deal_web/paradigms/story.ex` | the story runtime and behaviour |
| `lib/good_deal_web/stories/` | the eight stories |
| `lib/good_deal_web/live/cart_live/show.ex` | a page composing five stories |
| `lib/good_deal_web/paradigms/wiring.ex`, `drawing.ex` | checks and diagrams |
| `test/good_deal_web/live/wiring_test.exs` | coverage, story and clash tests |
