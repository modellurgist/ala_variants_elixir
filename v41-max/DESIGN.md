# V41-max design: feature components with a route table

A Phoenix LiveView design where each feature is a **LiveComponent panel**. A panel holds a pure state
module, handles its own browser events, renders its own region, and sends every output it doesn't show
itself to the page as a `{name, port, payload}` message. The page's wiring is **one `@routes` map**:
each `{name, port}` key lists route targets. One generic `handle_info` hands every message to
`Instance.route/3`, which delivers the payload to each target in turn. It might forward the payload to
another panel's input, assign it, flash a message, patch the URL, call a store, or start a task. Each
cross-panel update costs one message hop.

Use it when you want LiveComponent panels plus wiring you can read, test and draw as a single value. If
you'd rather write the routes as ordinary `handle_info` clauses, V49 has the same panels without the
route vocabulary.

## At a glance

| | |
|---|---|
| Wiring form | one `@routes` map per page: `%{{name, port} => [target, ...]}`, exposed as `routes/0` |
| Where feature state lives | inside each panel (a LiveComponent), as `:state` |
| Runtime | `Instance` (about 80 lines): `step/3`, `send_port_output/3`, `route/3` with nine target kinds |
| Store work | synchronous `call` and `feed` targets on configured instances; the payment runs as a `start_async` task |
| Coverage check | a test checks that every port each panel sends has a route, and that every `pass` target names a panel the page places |
| Diagram | `Drawing.mermaid/1` draws the route table |
| Message hops between components | one per cross-panel update (panel → page → panel) |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `ZeroCoupledWeb.CartPage`, `PortalPage`, `ProductLive.*`, `StoreConfig`, `CartSession` | pages: configuration, configured instances, panels placed in the template, the route table |
| State | `ZeroCoupled.Features.*` and `ZeroCoupled.Features.*.Panel` | stateful domain abstractions with declared ports (`Cart`, `Undo`, `SavedItems`, `Wishlist`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit`), and one panel per feature that runs it |
| Domain | `ZeroCoupled.Domain.*`, `ZeroCoupled.Actions.*`, `ZeroCoupled.Cart` | rule functions, configured store-work structs (`AddLine`, `PlaceOrder`, `StartPayment`), `SaveProduct`, the cart aggregate |
| Programming paradigms and foundation | `ZeroCoupledWeb.Paradigms.*`, `ZeroCoupled.Paradigms.*`, `ZeroCoupled.Catalog.*`, `ZeroCoupled.Foundation.*` | `Instance`, `Drawing`, the `Subscribed` `on_mount` hook, the state-machine table, generic UI components (rows, panes, tabs), stores, PubSub wrapper |

The state modules live under a `Features` namespace, but they're state abstractions, not Spray's
Features layer of user stories. In a new project, call the namespace `State`.

## Building block 1: a state module with ports

Each state module is a set of pure functions over its own struct. Each input returns
`{new_state, [port: payload]}`, and `ports/0` declares the inputs and outputs:

```elixir
def ports,
  do: %{
    in: [capture: :item, restore: :event, expire: :item_id],
    out: [captured: :item, restored: :item, expired: :item_id]
  }

def capture(%__MODULE__{pending: %{id: held}} = undo, item),
  do: {%{undo | pending: item}, [expired: held, captured: item]}
```

Outputs state facts (`changed`, `captured`, `ready_to_pay`), not commands. Configuration comes in once,
when the module is built. A state module does no I/O and never names a peer module.

## Building block 2: a panel

A panel is a LiveComponent that holds one feature:

- **Configuration** comes in as attributes: words (`t`, `empty_text`), rules (`pricing`), and **pull
  ports** for reads (`source={&Carts.list_items/1}`). A pull port is a function the panel calls, so the
  panel never names a store.
- **Inputs** arrive by `send_update(Panel, id: ..., input: payload)`. Each input has one `update/2`
  clause, and a last clause takes the configuration and loads the state on first update.
- **Browser events** go to the panel itself through `phx-target={@myself}`. Each `handle_event/3`
  decodes its params and steps the feature.
- **Outputs** go through a private `wire/2`. It shows some outputs itself (rows go to its stream, the
  summary goes to its assigns) and sends every other one to the page.
- `sent_port_outputs/0` is derived as the feature's out ports minus `@wired_here`, so the coverage test
  doesn't depend on a hand-kept list.

```elixir
defmodule ZeroCoupled.Features.Cart.Panel do
  use ZeroCoupledWeb, :live_component
  alias ZeroCoupled.Features.Cart
  alias ZeroCoupledWeb.Paradigms.Instance

  @wired_here [:rows]
  def sent_port_outputs, do: Keyword.keys(Cart.ports().out) -- @wired_here

  def update(%{receive: item}, s), do: {:ok, step(s, &Cart.receive(&1, item))}
  def update(%{confirm_removal: id}, s), do: {:ok, step(s, &Cart.confirm_removal(&1, id))}
  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_loaded()}

  def handle_event("remove_item", %{"item-id" => id}, s),
    do: {:noreply, step(s, &Cart.remove(&1, %{item_id: int(id)}))}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)

  defp wire(s, {:rows, {:removed, row}}), do: stream_delete(s, :cart_items, row)
  defp wire(s, {:rows, {_, row}}), do: stream_insert(s, :cart_items, row)
  defp wire(s, {:summary, summary} = out),
    do: s |> assign(summary: summary) |> Instance.send_port_output(:cart, out)
  defp wire(s, out), do: Instance.send_port_output(s, :cart, out)
end
```

Each panel writes its own send name (`:cart`) in its code. The page's route keys and the coverage test
use the same name. (V49 has the page pass the name in as an attribute.)

## Wiring: the page

```elixir
@routes %{
  {:cart, :summary} => [assign: :cart_summary],
  {:cart, :changed} => [call: &Carts.apply_change/1],
  {:cart, :removed} => [pass: {Undo.Banner, "undo", :capture}],
  {:cart, :saved} => [pass: {SavedItems.Panel, "saved", :stash}, flash: {:info, "Saved for later"}],
  {:undo, :expire} => [pass: {Undo.Banner, "undo", :expire}],
  {:undo, :restored} => [pass: {Cart.Panel, "cart", :receive}, flash: {:info, "Item restored"}],
  {:wishlist, :taken} => [
    feed: {:add_line, &AddLine.run/2, {Cart.Panel, "cart", :receive}},
    flash: {:info, "Added to cart"}
  ],
  {:checkout, :blocked} => [flash_by: {:error, @blocked}],
  {:checkout, :ready_to_pay} => [async: {:payment, :payment, &StartPayment.call/2}],
  {:payment, :succeeded} => [pass: {Checkout.Panel, "checkout", :succeeded}],
  {:checkout, :done} => [call: {:place_order, &PlaceOrder.place/2}, redirect: true],
  {:checkout, :step} => [patch: @step_paths],
  {:stock, :changed} => [pass: {Cart.Panel, "cart", :set_stock}]
}

def routes, do: @routes

def handle_info({_name, _port, _payload} = port_output, socket),
  do: {:noreply, Instance.route(socket, @routes, port_output)}

def handle_info(%Broadcast.Facts.StockChanged{} = change, socket),
  do: {:noreply, Instance.route(socket, @routes, {:stock, :changed, change})}

def handle_async(:payment, {:ok, {:ok, url}}, socket),
  do: {:noreply, Instance.route(socket, @routes, {:payment, :succeeded, url})}
```

Messages that don't come from a panel, such as PubSub facts and task results, are turned into
`{name, port, payload}` triples and routed through the same table. `route/3` uses `Map.fetch!`, so a
port with no route crashes the page.

The page's `mount/3` assigns the configuration: words (`texts`), the `pricing` rule instances, the
checkout flow table and step paths, and an `instances` map of configured store-work structs
(`%AddLine{carts: Carts, products: Products, cart_id: id}`, `%PlaceOrder{...}`, `%StartPayment{...}`).
The template places each panel with its id and configuration:

```heex
<.live_component module={Cart.Panel} id="cart" cart_id={@cart_id} pricing={@pricing}
  source={&Carts.list_items/1} wishlist_ids={@wishlist_ids} t={@texts.cart} ... />
```

## Route targets

| Target | Effect |
|---|---|
| `pass: {component, id, input}` | `send_update` the payload to a panel's input |
| `assign: name` | assign the payload on the page |
| `flash: {level, text}` | a fixed flash message |
| `flash_by: {level, texts}` | the flash text keyed by the payload |
| `patch: paths` | `push_patch` to the payload's path, when `paths` has one |
| `redirect: true` | redirect to the URL in the payload |
| `call: fun` / `call: {name, fun}` | call `fun.(payload)`, or `fun.(instance, payload)` with a configured instance, for its effect |
| `feed: {name, fun, {component, id, input}}` | pass `fun.(instance, payload)` to a panel's input |
| `async: {task, name, fun}` | run `fun.(instance, payload)` in a `start_async` task named `task` |

`name` refers to an entry in the page's `instances` assign. If the entry is missing, `instance!/2`
raises.

## Runtime: `Instance`

```elixir
def step(socket, fun, show) do
  {state, outputs} = fun.(socket.assigns.state)
  Enum.reduce(outputs, assign(socket, :state, state), &show.(&2, &1))
end

def send_port_output(socket, name, {port, payload}) do
  send(self(), {name, port, payload})
  socket
end

def route(socket, routes, {name, port, payload}),
  do: routes |> Map.fetch!({name, port}) |> Enum.reduce(socket, &deliver(&2, &1, payload))
```

`send(self(), ...)` puts the output in the page process's mailbox. The page handles it after the panel's
own event finishes, and that delay is the hop. `deliver/3` has one private clause per target kind.

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** each panel handles its own. Page-level controls (tabs, the Checkout button) send
  their events to the page.
- **URL steps:** the checkout panel sends `step`, and the page patches through `@step_paths`. LiveView
  doesn't let a component `push_patch` while it's updating. `handle_params` reads the step from the URL
  and passes it to the checkout panel as `requested_step`.
- **Timers:** the undo banner starts its own `Process.send_after(self(), {:undo, :expire, id}, ms)`. The
  message reaches the page, which routes it back to the banner's `expire` input
  (`{:undo, :expire} => [pass: {Undo.Banner, "undo", :expire}]`).
- **Store I/O:** panels read through pull ports. Writes go through route targets: `call` for
  `Carts.apply_change/1` and placing the order, `feed` for adding a line. Both run synchronously in the
  page process. The payment runs as an `async` task, and the page's `handle_async` clauses route its
  result back to checkout.
- **Hidden panels stay mounted.** `send_update` to an unmounted component raises, so the cart's panels
  sit hidden in a `pane` behind the checkout screen.
- **PubSub:** an `on_mount` hook subscribes the page. A `StockChanged` fact is routed like a port output;
  facts the page doesn't show get an empty clause.
- **Product forms** are the `phx.gen.live` form component, saving through `SaveProduct`.

## UI

Generic components in `ZeroCoupled.Catalog` take words and event names as attributes: rows, the
`pane`/`only_on`/`tabs` set in `Panes`, stock badges and action buttons. Panels render with these and
pass `phx-target={@myself}` so events come back to them.

## Checks

`WiringTest` collects every `{name, port}` each placed panel sends, through `sent_port_outputs/0`, plus
the timer and PubSub keys. It asserts that each one has a route, and that every `pass` target names a
panel module the page places. It doesn't check for routes that nothing sends. `DrawingTest` checks that
the drawn diagram contains known edges.

## Applying it to another project

1. Write each feature as a pure state module with `ports/0`.
2. Write one LiveComponent per feature. Give it configuration as attributes (pull ports for reads), one
   `update/2` clause per input, its own `handle_event/3`s, and a `wire/2` that shows some outputs and
   sends the rest with `Instance.send_port_output/3`. Derive `sent_port_outputs/0` from `ports/0` minus
   `@wired_here`.
3. Copy `Instance` and `Drawing` into your paradigm layer. Add or drop target kinds as your pages need.
4. On each page, place each panel with an id, keep configured I/O instances in an `instances` assign,
   write the `@routes` map, expose it as `routes/0`, and add the generic `handle_info`. Turn PubSub
   facts and `handle_async` results into `{name, port, payload}` and route them through the same table.
5. Add the coverage test, and draw the table with `Drawing.mermaid/1` for reviews.

## Trade-offs and limits

- One message hop per cross-panel update, and panels must stay mounted to receive `send_update`.
- The route targets are a nine-word vocabulary on top of LiveView. They're compact but have to be
  learned (familiarity 4).
- Panels write their own send names, so the name a route key uses is fixed by the panel's code rather
  than given by the page.
- Writes through `call` and `feed` block the page process while the store works; only the payment is a
  task.
- The coverage test checks one direction only: a route for a port nothing sends goes unnoticed.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/pages/cart_page.ex` | the route table, configuration and panel placement |
| `lib/zero_coupled/features/cart/panel.ex` | a feature panel |
| `lib/zero_coupled/features/undo/` | the undo banner with its own timer |
| `lib/zero_coupled_web/paradigms/instance.ex` | the runtime and the route target kinds |
| `lib/zero_coupled_web/paradigms/drawing.ex` | the Mermaid drawer |
| `test/zero_coupled_web/pages/wiring_test.exs` | the coverage and drawing tests |
