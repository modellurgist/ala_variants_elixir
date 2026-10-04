# V48 design: plain clauses with named instances

A Phoenix LiveView design that meets the full [ALA Checklist](https://github.com/modellurgist/ala_checklist).
Each page holds its features as plain values in its assigns, runs every feature step through a small
runner, and wires every feature output with one private `wire/3` clause per port. The configured
store-work instances (add a line, charge a payment, settle an order) live in one `instances` map built
at mount, and a clause names the instance it uses instead of reading it from assigns, so a misnamed
instance fails loudly where it's named. There are no LiveComponents, so no message hops between
components: a click runs the whole chain of effects inside one `handle_event`.

Use it for pages under about 500 lines (Spray's size limit for one abstraction). V50 is the same design
without the named instances, a little more familiar; V46 splits this design along user stories.

## At a glance

| | |
|---|---|
| Wiring form | one `defp wire(socket, feature_key, {port, payload})` clause per declared output port, in the page |
| Where feature state lives | the page's assigns, one key per feature |
| Runner | `Steps.run/4`, `Steps.feed/6`, `Steps.call/3`, `Steps.async/4` (about 90 lines with the landing points) |
| Configured instances | one `instances` map in assigns; clauses name them (`{:charge, &Charge.call/2}`) |
| Async work | the payment only, by `Steps.async/4` (LiveView's `start_async`) and `handle_async` |
| Coverage check | a one-line test per page (`Wiring.gaps/1`); an optional compile-time check |
| Diagram | `Drawing.mermaid/1` draws the page's wiring from its `wire/3` clauses |
| Message hops between components | none |

## Layers

Knowledge dependencies only point down this list. A call into a peer in the same layer is a defect,
except inside the application.

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `GoodDealWeb.*Live.*`, `GoodDealWeb.CartSession`, `GoodDealWeb.CheckoutMetadata`, `GoodDeal.Catalog` | pages (mount, handlers, `wire/3` clauses, templates), the router, store-wide configuration and words |
| State | `GoodDeal.State.*` | stateful domain abstractions with declared ports: `Cart`, `Undo`, `SavedItems`, `Wishlist`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit`, `RecordEdit`, `PageUI` |
| Domain | `GoodDeal.Domain.*`, `GoodDeal.Actions.*`, `GoodDeal.Cart`, `GoodDeal.Lines` | product-free rules and configured instances: pricing functions, `StockStatus`, `AddLine`, `Charge`, `SettleOrder`, `PlaceOrder`; the cart aggregate and plain line functions |
| Programming paradigms and foundation | `GoodDealWeb.Paradigms.*`, `GoodDeal.Paradigms.*`, `GoodDeal.Components.*`, `GoodDeal.Foundation.*` | the runner (`Steps`), wiring checks, drawer, `on_mount` subscription hook, state-machine table, generic UI components, stores, PubSub wrapper, payment gateway |

The layer map lives outside the app, in the linter's configuration: a list of module-name patterns
per layer, with the application layer allowed internal calls and every lower layer checked for peer
edges.

## Building block: a state module with ports

Every feature is a module of pure functions over its own struct. Each input is a function
`input(state, payload) -> {new_state, outputs}`, where `outputs` is a keyword list of
`port: payload`. `ports/0` declares inputs and outputs so tests and tools can check the wiring.

```elixir
defmodule GoodDeal.State.Undo do
  defstruct pending: nil

  def ports,
    do: %{
      in: [capture: :item, restore: :event, expire: :item_id],
      out: [captured: :item, restored: :item, expired: :item_id]
    }

  def new(_opts), do: %__MODULE__{}

  def capture(%__MODULE__{pending: %{id: held}} = undo, item),
    do: {%{undo | pending: item}, [expired: held, captured: item]}

  def capture(%__MODULE__{} = undo, item), do: {%{undo | pending: item}, [captured: item]}
  # restore/2, expire/2 ...
end
```

Rules for these modules:

- **Outputs announce, they don't command.** An output says what happened (`captured`, `restored`,
  `checkout_requested`), never where it goes. No stream names, topics, flash text or page names.
- **Configuration comes in once**, through `new/1` (rates, codes, a changeset function, a stock rule),
  and run-time data comes after it in each call.
- **No I/O.** A state module never calls a store. Store work is done by configured domain instances
  (`AddLine`, `Charge`) that the page wires in.
- **No peers.** `Cart` never calls `Undo`; the page wires `removed` to `capture`.
- **A consumer gets only the data it needs.** Checkout receives `{cart_id, items}`, not the cart.

## Wiring: the page

A page module has four parts, top to bottom.

1. **Configuration.** Module attributes for the page's words and flows (`@texts`, `@checkout_flow`,
   `@step_paths`, `@milestones`), and `features/0`, the map from wiring key to state module that the
   coverage test reads.
2. **`mount/3`** builds each feature and each configured store instance as a plain assign, and loads
   initial data through the runner.
3. **Handlers.** One `handle_event` clause per browser event, each decoding params and running one
   feature step. `handle_info` clauses route timer ticks and PubSub facts; `handle_async` routes a
   task's outcome. Handlers only forward.
4. **`wire/3` clauses**, one per declared output port, each saying where that output goes.

```elixir
@features %{cart: Cart, undo: Undo, saved: SavedItems, wishlist: Wishlist, ui: PageUI, checkout: Checkout}
def features, do: @features

def mount(_params, session, socket) do
  cart_id = CartSession.fetch(session)
  pricing = %{shipping: CalculateShipping.new(Catalog.rates()), ...}

  {:ok,
   socket
   |> assign(
     cart: GoodDeal.Cart.new(cart_id: cart_id, pricing: pricing),
     undo: Undo.new([]),
     instances: %{
       add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
       charge: %Charge{gateway: ..., metadata: &CheckoutMetadata.for_cart/1},
       settle: %SettleOrder{orders: Orders, carts: Carts, products: Products, ...}
     },
     ...
   )
   |> stream(:cart_items, [])
   |> Steps.feed(:cart, &Cart.load/2, &Carts.list_items/1, cart_id, &wire/3)}
end

def handle_event("remove_item", %{"item-id" => id}, socket),
  do: {:noreply, run(socket, :cart, &Cart.remove(&1, %{item_id: int(id)}))}

defp run(socket, key, step), do: Steps.run(socket, key, step, &wire/3)

# {feature, port} → where it wires on this page
defp wire(s, :cart, {:rows, change}), do: Steps.stream_change(s, :cart_items, change)
defp wire(s, :cart, {:summary, summary}), do: assign(s, :summary, summary)
defp wire(s, :cart, {:removed, item}), do: run(s, :undo, &Undo.capture(&1, item))

defp wire(s, :undo, {:captured, item}),
  do: s |> assign(:undo_pending, true) |> Steps.start_timer(:undo, item, Catalog.undo_window_ms())

defp wire(s, :wishlist, {:taken, product}),
  do:
    s
    |> Steps.feed(:cart, &Cart.receive/2, {:add_line, &AddLine.run/2}, product, &wire/3)
    |> put_flash(:info, "Added to cart")

defp wire(s, :checkout, {:ready_to_pay, payment}),
  do: Steps.async(s, :payment, {:charge, &Charge.call/2}, payment)

defp wire(s, :checkout, {:done, reference}),
  do: s |> Steps.call({:settle, &SettleOrder.run/2}, reference) |> push_navigate(to: ~p"/cart/success")
```

What a `wire/3` clause may contain: running another feature's input (`run`), feeding one with a
source's answer (`Steps.feed`), asking a named instance for its effect (`Steps.call`) or in a task
(`Steps.async`), and landing an output on the page (`assign`, `Steps.stream_change`, `put_flash`,
`Steps.patch`, `Steps.start_timer`, `push_navigate`, a store call such as `Carts.apply_change/1`). No
clause reads `s.assigns` for an instance. What it may not contain: `if`, `case` on data, arithmetic, or holding one
feature's result to hand to another (use `feed` for that).

There is deliberately no catch-all `wire/3` clause, so an unwired output crashes the page in tests,
and the coverage test finds it before that.

## Runtime: the runner

```elixir
defmodule GoodDealWeb.Paradigms.Steps do
  def run(socket, key, step, wire) do
    {state, outputs} = step.(socket.assigns[key])
    Enum.reduce(outputs, assign(socket, key, state), &wire.(&2, key, &1))
  end

  def feed(socket, key, input, source, payload, wire),
    do: run(socket, key, &input.(&1, ask(socket, source, payload)), wire)

  def call(socket, source, payload) do
    ask(socket, source, payload)
    socket
  end

  def async(socket, name, {instance_name, fun}, payload) do
    instance = instance!(socket, instance_name)
    start_async(socket, name, fn -> fun.(instance, payload) end)
  end

  defp ask(socket, {name, fun}, payload) when is_atom(name) and is_function(fun, 2),
    do: fun.(instance!(socket, name), payload)

  defp ask(_socket, fun, payload) when is_function(fun, 1), do: fun.(payload)
  defp ask(_socket, fun, _payload) when is_function(fun, 0), do: fun.()

  defp instance!(socket, name) do
    case socket.assigns[:instances] do
      %{^name => instance} -> instance
      _ -> raise ArgumentError, "no configured instance #{inspect(name)} in @instances"
    end
  end
  # stream_change/3, patch/3, start_timer/4, stop_timer/2: landing points
end
```

`run` steps one feature, stores its new value, and folds each output through the page's `wire/3`.
`feed` runs a feature input on what a source answers, so a page never holds one abstraction's answer
to pass to another. A source is a function of the payload, a function of nothing (a plain read), or
`{name, fun}`, which calls `fun.(instance, payload)` on the instance named `name` in the `instances`
map. `call` asks a source for its effect only; `async` asks it in a LiveView task. Because every wire runs in the same
process and the same call, effects happen in output order with no message between them.

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** one `handle_event` per event name, decoding string params (`int/1`,
  `String.to_existing_atom/1`) and running one feature input.
- **URL steps:** the checkout flow is a state machine (`GoodDeal.Paradigms.Transitions`, a table of
  `{from, event, to}`) inside `State.Checkout`, configured with the page's `@checkout_flow`.
  `handle_params/3` looks the URL segment up in `@steps_by_url` and calls `Checkout.goto/2`; the
  feature decides whether to honour it. A `step` output lands as `Steps.patch(@step_paths, step)`.
- **Timers:** the undo window is `Steps.start_timer(:undo, item, ms)`, which sends `{:timer, :undo,
  item}` back to the page; one `handle_info` clause routes it to `Undo.expire/2`.
- **Async:** the payment is a LiveView task started in a `wire/3` clause with `Steps.async/4`; three
  `handle_async(:payment, ...)` clauses route success, failure and a crash to `Checkout.succeeded/2` and `Checkout.failed/2`.
- **Store I/O:** reads go through `Steps.feed` with a plain function capture (`&Carts.list_items/1`).
  Writes are outputs (`changed`) the page wires to a store call. Multi-step store work is a domain
  instance configured with its stores (`%SettleOrder{orders: Orders, carts: Carts, ...}`), kept in the
  `instances` map and named in the clause that uses it (`Steps.call({:settle, &SettleOrder.run/2}, ref)`).
- **PubSub:** an `on_mount` hook in the paradigm layer subscribes, configured on the page
  (`on_mount {Subscribed, {Broadcast, :subscribe}}`), so `mount/3` has no `connected?` branch.
  `handle_info` routes each fact to a feature input.

## UI

- Templates place generic components (`GoodDeal.Components.*`): `tabs`, `pane`, `only_on`,
  `stream_list`, `none`, row components, `cart_summary`, `notice`, `primary_button`, `card`. Each takes
  its words and its event names as attributes, so the components know no page.
- No comparisons, arithmetic or loops in a page template: a component does the iterating (`stream_list`),
  the comparing (`pane current={...} name={...}`), or a feature projects the boolean into the row.
- The page keeps every word in a `@texts` map, merging in store-wide words from `GoodDeal.Catalog`.

## Checks

- `Wiring.gaps(PageModule)` reads the page's own source, collects the `wire/3` clause heads, and
  compares them with every output each feature in `features/0` declares, both ways. Each page's
  coverage test is one line:

  ```elixir
  assert Wiring.gaps(GoodDealWeb.CartLive.Show) == %{unwired: [], unknown: []}
  ```

- `use GoodDealWeb.Paradigms.Wiring` (optional, unused by the pages) makes the same check at compile
  time with `@on_definition` and `@before_compile`.
- `Drawing.mermaid(PageModule)` draws the page's wiring as a Mermaid flowchart from the same clauses.
- The shared acceptance tests drive the pages through `Phoenix.LiveViewTest`.
- `ala_lint` with a layer map checks the layers, literals, ports and the page's composition-only rule.

## Applying it to another project

1. **List your features per page** and write each as a state module: a struct, `new/1` for
   configuration, one function per input returning `{state, [port: payload]}`, and `ports/0`. Name
   outputs as facts. Keep I/O out.
2. **Write the domain below them**: pure rule functions, and configured instances for store work (a
   struct holding its stores and ids, with one `run`/`call` function).
3. **Copy the runner** (`run`, `feed`, `call`, `async`, the instance lookup, and the landing points
   you need) into a paradigm-layer module.
4. **Write each page** in the four parts above: configuration and `features/0`; `mount/3` assigning each
   feature, plus one `instances` map of configured store-work instances; one forwarding handler per
   event; one `wire/3` clause per output port, naming instances as `{name, fun}`.
5. **Move words and calibration up**: page words in a `@texts` map, store-wide values in one
   application module the pages read, and everything passed down as configuration.
6. **Add the coverage test** (copy `Wiring.gaps/1`) and, if you want it, the drawer.
7. **Put subscriptions in an `on_mount` hook** and route each fact in `handle_info`.
8. **Run `ala_lint`** with a layer map naming your four layers, and fix what it finds.

## Trade-offs and limits

- The `{name, fun}` source is the one piece of vocabulary beyond plain LiveView; it costs a point of
  familiarity against V50, which reads instances from assigns instead.
- Only a source reader shows the wiring; it isn't a value you can inspect at run time.
- Store work is synchronous, except the payment.
- The cart page is about 500 lines with its template, at the size where Spray adds a Features layer.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/good_deal_web/live/cart_live/show.ex` | the full page shape: configuration, mount, handlers, `wire/3` |
| `lib/good_deal_web/paradigms/steps.ex` | the runner, with named instances |
| `lib/good_deal_web/paradigms/wiring.ex`, `drawing.ex` | coverage check and diagram |
| `lib/good_deal/state/cart.ex`, `undo.ex`, `checkout.ex` | state modules with ports |
| `lib/good_deal/domain/add_line.ex`, `charge.ex`, `settle_order.ex` | configured store-work instances |
| `lib/good_deal/components/` | generic UI components |
| `test/good_deal_web/live/wiring_test.exs` | coverage and diagram tests |
