# V41 design: feature components

A Phoenix LiveView design in the shape `phx.gen.live` produces. Each feature is a **LiveComponent
panel** that holds a pure state module, handles its own browser events, renders its own region, and
does its own store work through stores and domain instances that the page passes in. A panel sends any
output it doesn't handle itself to the page as a `{name, port, payload}` message. The page's
`handle_info` clauses, one per sent port, are the wiring. Each clause forwards the output to another
panel with `send_update`, assigns it, flashes a message, or patches the URL. Each cross-panel update
costs one message hop, while an action that stays inside one panel needs no hop.

This is the first version of the design. V41-max replaces the clauses with a route table and moves
store work out of the panels. V49 keeps the clauses and moves store work into page tasks.

## At a glance

| | |
|---|---|
| Wiring form | one page `handle_info({name, port, payload}, socket)` clause per sent port, through a private `pass/4` helper |
| Where feature state lives | inside each panel (a LiveComponent), as `:state` |
| Runtime | `Instance.step/3` and `Instance.send_port_output/3` (18 lines), plus LiveView itself |
| Store work | in the panels, through stores and domain instances passed in as attributes (`store`, `add_line`, `place_order`, `gateway`) |
| Coverage check | a test sends every port each panel declares to the page and fails if `handle_info` has no clause for it |
| Diagram | none |
| Message hops between components | one per cross-panel update (panel → page → panel) |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `ZeroCoupledWeb.CartPage`, `PortalPage`, `ProductLive.*` | pages: configuration as module attributes, `mount/3` assigning it, panels placed in the template, `handle_info` wiring |
| State | `ZeroCoupled.Features.*` and `ZeroCoupled.Features.*.Panel` | pure stateful modules with declared ports (`Cart`, `Undo`, `SavedItems`, `Wishlist`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit`) and one panel per feature |
| Domain | `ZeroCoupled.Domain.*`, `ZeroCoupled.Actions.*`, `ZeroCoupled.Cart` | configured rule structs (`CalculateShipping`, `ValidatePromo`, `CalculateGiftWrapCost`, `VolumeTier`), store-work structs (`AddLine`, `PlaceOrder`), the cart aggregate |
| Programming paradigms and foundation | `ZeroCoupledWeb.Paradigms.*`, `ZeroCoupled.Paradigms.*`, `ZeroCoupled.Catalog.*`, `ZeroCoupled.Foundation.*` | `Instance`, the state-machine table, generic row components, stores, PubSub wrapper |

The state modules live under a `Features` namespace, but they're state abstractions, not Spray's
Features layer of user stories. In a new project, call the namespace `State`.

## Building block 1: a state module with ports

Each state module is a set of pure functions over its own struct. Each input returns
`{new_state, [port: payload]}`, and `ports/0` declares the inputs and outputs. A state module never
does I/O. It sends a request as an output (`:persist`, `:payment`), and its panel carries the request
out.

## Building block 2: a panel

- **Configuration** comes in as attributes: `cart_id`, `pricing` (a map of configured rule structs),
  texts, and the I/O it may use: `store={Carts}`, `add_line={@add_line}`, `place_order={@place_order}`,
  `gateway`, `stock_levels`.
- **Loading:** on first `update/2`, the panel builds its state and loads rows through `store`.
- **Inputs** arrive by `send_update(Panel, id: ..., input: payload)`, with one `update/2` clause per
  input.
- **Browser events** go to the panel itself through `phx-target={@myself}`.
- **Outputs** go through a private `wire/2`. It handles some outputs locally, through stream changes,
  assigns and store writes, and sends the rest to the page.

```elixir
defmodule ZeroCoupled.Features.Cart.Panel do
  use ZeroCoupledWeb, :live_component
  alias ZeroCoupled.Domain.AddLine
  alias ZeroCoupled.Features.Cart
  alias ZeroCoupledWeb.Paradigms.Instance

  def sent_port_outputs, do: [:summary, :removed, :saved, :line, :promo_applied, :promo_rejected]

  def update(%{receive: item}, s), do: {:ok, step(s, &Cart.receive(&1, item))}

  def update(%{add_product: product}, s),
    do: {:ok, step(s, &Cart.receive(&1, AddLine.run(s.assigns.add_line, s.assigns.cart_id, product)))}

  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_loaded()}

  def handle_event("remove_item", %{"item-id" => id}, s),
    do: {:noreply, step(s, &Cart.remove(&1, %{item_id: int(id)}))}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)

  defp wire(s, {:rows, {_, row}}), do: stream_insert(s, :cart_items, row)
  defp wire(s, {:persist, change}), do: (s.assigns.store.apply_change(change); s)
  defp wire(s, out), do: Instance.send_port_output(s, :cart, out)
end
```

The checkout panel owns its whole flow. It runs the payment as its own `start_async` task and handles
the result in its `handle_async`. When the payment succeeds, it places the order with
`PlaceOrder.run(place_order, cart_id)` and redirects.

## Wiring: the page

```elixir
def handle_info({:cart, :removed, item}, socket),
  do: {:noreply, pass(socket, Undo.Banner, "undo", capture: item)}

def handle_info({:undo, :restored, item}, socket),
  do: {:noreply, socket |> pass(Cart.Panel, "cart", receive: item) |> put_flash(:info, "Item restored")}

def handle_info({:wishlist, :taken, product}, socket),
  do: {:noreply, socket |> pass(Cart.Panel, "cart", add_product: product) |> put_flash(:info, "Added to cart")}

def handle_info({:checkout, :step, step}, socket), do: {:noreply, patch(socket, @step_paths, step)}

def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket),
  do: {:noreply, pass(socket, Cart.Panel, "cart", set_stock: %{product_id: id, stock: stock})}

def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}

defp pass(socket, module, id, input) do
  send_update(module, [{:id, id} | input])
  socket
end
```

Configuration lives as module attributes on the page: rates, promo codes, the checkout flow table, step
paths and messages. `mount/3` builds the configured instances from them
(`CalculateShipping.new(@rates)`, `%AddLine{carts: Carts, products: Products}`, `%PlaceOrder{...}`), and
the template hands them to the panels. Every flash text is on the page. There's no catch-all
`handle_info`.

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

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** each panel handles its own. The tab switch and the Checkout button send their
  events to the page.
- **URL steps:** a flow panel sends `step`, and the page patches through `@step_paths`. LiveView raises
  if a component patches during `update/2`. `handle_params` passes the URL's step back to the panel as
  `requested_step`, and the panel follows it only along `url_edges`.
- **Timers:** the undo banner starts `Process.send_after(self(), {:undo, :expire, id}, ms)`. The page
  passes the message back to the banner's `expire` input.
- **Store I/O** happens inside the panels, through the stores and instances passed in. The payment runs
  as a task on the checkout panel.
- **Hidden panels stay mounted.** `send_update` to an unmounted component raises, so the cart page keeps
  its index panels mounted, hidden behind checkout, and the portal does the same behind its review.
- **PubSub:** the page subscribes, and passes each fact it uses to a panel.

## Checks

`WiringTest` calls each page's `handle_info` with a sample of every port each placed panel lists in
`sent_port_outputs/0`, plus the timer message and both broadcasts. The test fails only on a
`FunctionClauseError` from the page's own `handle_info`. A clause that exists but chokes on the sample
payload still counts as routed. The panels' `sent_port_outputs/0` lists are written by hand.

## Applying it to another project

1. Write each feature as a pure state module with `ports/0`. Have it send I/O requests as outputs.
2. Write one LiveComponent per feature, configured by attributes that include the stores and domain
   instances it may use. Give it one `update/2` clause per input, its own `handle_event/3`s, and a
   `wire/2` that applies stream and assign changes, carries out I/O requests, and sends the rest with
   `Instance.send_port_output/3`.
3. Copy `Instance` (two functions) into your paradigm layer.
4. On each page, keep configuration as module attributes, build the configured instances in `mount/3`,
   place each panel with an id, and write one `handle_info` clause per sent port.
5. Add the coverage test that sends every declared port to the page.

## Trade-offs and limits

- One message hop per cross-panel update, and panels must stay mounted to receive `send_update`.
- Panels run their own store work, so the I/O is spread across the panels' `wire/2` clauses.
  V41-max and V49 move it to the page.
- The wiring is about 20 clauses plus each panel's `@moduledoc`, not one value you can draw.
- The two pages repeat the shipping rates and the `"undo"` instance id. Some screen labels stay inside
  the panels' templates.
- `sent_port_outputs/0` is hand-kept, so it can drift from `ports/0`.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/pages/cart_page.ex` | configuration, `handle_info` wiring and panel placement |
| `lib/zero_coupled/features/cart/panel.ex` | a panel that loads and writes through its configured store |
| `lib/zero_coupled/features/checkout/panel.ex` | a flow panel with its own payment task and order placement |
| `lib/zero_coupled_web/paradigms/instance.ex` | the two-function runtime |
| `test/zero_coupled_web/pages/wiring_test.exs` | the coverage test |
