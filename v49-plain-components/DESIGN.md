# V49 design: plain components

A Phoenix LiveView design in the shape `phx.gen.live` already gives you: each feature is a
**LiveComponent panel** that holds a pure state module, handles its own browser events, renders its own
region, and sends every output it doesn't show itself to the page as a `{name, port, payload}`
message. The page's `handle_info` clauses, one per sent port, are the wiring: each forwards the
output to another panel with `send_update`, lands it on the page, or starts store work as a LiveView
task. It meets the full [ALA Checklist](https://github.com/modellurgist/ala_checklist), at the cost of one
message hop per cross-panel update.

Use it when your team already builds pages from LiveComponents and wants each region's events, state
and markup in one file. V50 reaches the same score with no hops by holding features as plain values.

## At a glance

| | |
|---|---|
| Wiring form | one page `handle_info({name, port, payload}, socket)` clause per sent port |
| Where feature state lives | inside each panel (a LiveComponent), as `:state` |
| Runtime | `Instance.step/3` and `Instance.send_port_output/3` (about 20 lines), plus LiveView itself |
| Store work | LiveView tasks (`start_async`) for adding a line, placing an order, the payment and saving a product |
| Coverage check | a test reads the page's `handle_info` heads and checks them against every port each panel sends, both ways |
| Diagram | `Drawing.mermaid/1` draws the page's wiring from its `handle_info` and `handle_async` clauses |
| Message hops between components | one per cross-panel update (panel → page → panel) |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `ZeroCoupledWeb.CartPage`, `PortalPage`, `ProductLive.*`, `StoreConfig`, `CartSession` | pages: configuration, configured instances, panels placed in the template, `handle_info`/`handle_async` wiring |
| State | `ZeroCoupled.State.*` and `ZeroCoupled.State.*.Panel` | stateful domain abstractions with declared ports (`Cart`, `Undo`, `SavedItems`, `Wishlist`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit`), and one panel per feature that runs it |
| Domain | `ZeroCoupled.Domain.*`, `ZeroCoupled.Actions.*`, `ZeroCoupled.Cart`, `ZeroCoupled.Lines` | rule functions, configured store-work instances (`AddLine`, `PlaceOrder`, `StartPayment`, `SaveProduct`), the cart aggregate, plain line functions |
| Programming paradigms and foundation | `ZeroCoupledWeb.Paradigms.*`, `ZeroCoupled.Catalog.*`, `ZeroCoupled.Foundation.*` | `Instance`, `Drawing`, the `on_mount` hook, generic UI components (rows, panes, a generic `RecordForm` LiveComponent), stores, PubSub wrapper |

## Building block 1: a state module with ports

Pure functions over the module's own struct; each input returns `{new_state, [port: payload]}`; `ports/0`
declares inputs and outputs. Outputs announce facts; configuration comes in once; no I/O, no peers;
checkout gets `{cart_id, items}`, not the cart.

## Building block 2: a panel

A panel is a LiveComponent that holds one feature and is placed and named by the page:

- **Configuration** comes in as attributes: the page's `name` for it, its words (`t`), its rules, and a
  **pull port** for reads (`source={&Carts.list_items/1}`), a function it calls rather than a store it
  names.
- **Inputs** arrive by `send_update(Panel, id: ..., port: payload)`; one `update/2` clause per input.
- **Browser events** are its own: `handle_event/3` clauses with `phx-target={@myself}`, each decoding
  params and stepping the feature.
- **Outputs**: its private `wire/2` lands the ones it shows (rows to its stream, the summary to its own
  assigns) and sends every other one to the page.

```elixir
defmodule ZeroCoupled.State.Cart.Panel do
  use ZeroCoupledWeb, :live_component
  alias ZeroCoupled.State.Cart
  alias ZeroCoupledWeb.Paradigms.Instance

  # outputs this instance shows itself; every other port its feature declares is sent
  @wired_here [:rows]
  def sent_port_outputs, do: Keyword.keys(Cart.ports().out) -- @wired_here

  def update(%{receive: item}, s), do: {:ok, step(s, &Cart.receive(&1, item))}
  def update(%{confirm_removal: id}, s), do: {:ok, step(s, &Cart.confirm_removal(&1, id))}

  def handle_event("remove_item", %{"item-id" => id}, s),
    do: {:noreply, step(s, &Cart.remove(&1, %{item_id: int(id)}))}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)

  defp wire(s, {:rows, {_, row}}), do: stream_insert(s, :cart_items, row)
  defp wire(s, {:summary, summary} = out),
    do: s |> assign(summary: summary) |> Instance.send_port_output(s.assigns.name, out)
  defp wire(s, out), do: Instance.send_port_output(s, s.assigns.name, out)
end
```

A panel sends under the name the page gave it (`name={:cart}`), never a name written in its own code,
so only the page knows which clause matches.

## Wiring: the page

```elixir
def handle_info({:cart, :removed, item}, socket) do
  send_update(Undo.Banner, id: "undo", capture: item)
  {:noreply, socket}
end

def handle_info({:undo, :restored, item}, socket) do
  send_update(Cart.Panel, id: "cart", receive: item)
  {:noreply, put_flash(socket, :info, "Item restored")}
end

def handle_info({:cart, :summary, summary}, socket), do: {:noreply, assign(socket, :cart_summary, summary)}

# storing the line is I/O; LiveView's task carries the stored line to the cart
def handle_info({:wishlist, :taken, product}, socket) do
  add_line = socket.assigns.instances.add_line
  {:noreply, socket |> start_async(:add_line, fn -> AddLine.run(add_line, product) end) |> put_flash(:info, "Added to cart")}
end

def handle_async(:add_line, {:ok, line}, socket) do
  send_update(Cart.Panel, id: "cart", receive: line)
  {:noreply, socket}
end
```

Each clause only forwards: `send_update` to a panel input, `assign`, `put_flash`, `push_patch`,
`redirect`, a store call, or `start_async` on a configured instance kept in the page's `instances`
map. There's no catch-all clause, so a port nobody wires crashes the page in tests.

The template places the panels, giving each its id, name, words and pull ports:

```heex
<.live_component module={Cart.Panel} id="cart" name={:cart} cart_id={@cart_id} pricing={@pricing}
  source={&Carts.list_items/1} wishlist_ids={@wishlist_ids} t={@texts.cart}>
  <button phx-click="start_checkout" ...>Checkout · {@cart_summary.total}</button>
</.live_component>
```

The page passes its Checkout button into the cart panel as slot content; a button without
`phx-target` sends its event to the page.

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
```

`send(self(), ...)` puts the output in the page process's mailbox, so the page handles it after the
panel's own event finishes. That's the hop.

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** each panel handles its own; page-level buttons send to the page.
- **URL steps:** the checkout panel sends `step`; the page patches through its `@step_paths` table, since
  LiveView doesn't let a component `push_patch` during its update.
- **Timers:** the undo banner panel starts its own window timer and sends `expire`; the page routes it.
- **Store I/O:** reads through pull ports; writes and multi-step work through `start_async` on a
  configured instance, with `handle_async` routing the answer back to a panel's input.
- **Hidden panels stay mounted.** `send_update` to an unmounted component raises, so the cart's panels
  stay mounted (hidden) behind the checkout screen.
- **PubSub:** an `on_mount` hook subscribes; `handle_info` routes each fact to a panel with `send_update`.

## UI

Generic components in `ZeroCoupled.Catalog` (rows, panes, parts) take words and event names as
attributes. Product forms use a generic `RecordForm` LiveComponent configured with the record's
changeset function, fields and words, which saves through the page's `SaveProduct` task.

## Checks

The coverage test reads every `handle_info({name, port, _}, _)` head from the page's source, collects
every port each panel sends (`sent_port_outputs/0`, derived from its feature's `ports/0`), and checks the
two sets are equal: no unwired port and no clause for a port nothing sends.

## Applying it to another project

1. Write each feature as a pure state module with `ports/0`.
2. Write one LiveComponent per feature: configuration as attributes (including a `name` and pull ports
   for reads), one `update/2` clause per input, its own `handle_event/3`s, and a `wire/2` that lands
   what it shows and sends the rest with `Instance.send_port_output/3`.
3. Copy `Instance` (two functions) into your paradigm layer.
4. On the page, place each panel with an id and a name, keep configured I/O instances in an `instances`
   assign, and write one `handle_info` clause per sent port.
5. Run store work as `start_async` tasks and route `handle_async` results to panel inputs.
6. Add the clause-head coverage test.

## Trade-offs and limits

- One message hop per cross-panel update, and panels must stay mounted to receive `send_update`.
- Familiarity 5: nothing beyond LiveView's own vocabulary, plus two small functions.
- A held judgement: the panels render their own markup, so a strict reviewer could read them as
  page-specific sub-components rather than stateful domain UI abstractions.
- Store work through tasks keeps the page responsive, but two quick clicks can finish out of order.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/pages/cart_page.ex` | the page's `handle_info` wiring and panel placement |
| `lib/zero_coupled/state/cart/panel.ex` | a feature panel |
| `lib/zero_coupled_web/paradigms/instance.ex` | the two-function runtime |
| `lib/zero_coupled/catalog/record_form.ex` | the generic record form |
| `test/zero_coupled_web/pages/wiring_test.exs` | the clause-head coverage test |
