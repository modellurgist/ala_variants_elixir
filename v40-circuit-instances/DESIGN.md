# V40 design: circuit instances

A Phoenix LiveView design where each page builds a **circuit** at mount. A circuit is a set of named
instances plus wires from `{instance, port}` to `{instance, input}`. Every instance, whether a feature,
a data source, a transform or a UI sink, implements one protocol, `Ports.Step`. Pushing data into an
instance delivers its outputs along the wires, depth first. Sinks emit LiveView effects on a `:ui`
port, and a small `Runner` applies those effects to the socket.

The template places **UI instances** (LiveComponents). Each one handles its own browser events by
sending a push into a named circuit input. The page handles no browser events of its own.

Use it as a study of the "everything is an instance on a dataflow graph" form. Later variants keep the
idea of wiring as one value (V39-max, V47) or as clauses (V48, V50), but drop the hops and most of the
named sink instances.

## At a glance

| | |
|---|---|
| Wiring form | `circuit/1` on each page: `Circuit.new(parts)` followed by one `Circuit.wire/3` per wire |
| Where feature state lives | inside the circuit's parts (`Adapter` structs), in the page's `:circuit` assign |
| Runtime | `Circuit` (push and route), `Adapter`, about a dozen sink and source structs, `Runner` (62 lines), `Emitter` |
| Store work | `FromStore` (reads), `ToStore` (writes), `Via` (a transform, used for page store functions), `ToAsync` (tasks) |
| Coverage check | none; an unwired output that isn't on a `:ui` port is dropped |
| Diagram | none drawn, though the circuit is a graph value |
| Message hops between components | two per click (instance → page → circuit → instance) |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `ZeroCoupledWeb.CartPage`, `PortalPage`, `CartLive.*` and `PortalLive.*` instances, `ProductLive.*` | pages (configuration, `circuit/1`, mount, three generic handlers, template), UI instances |
| State | `ZeroCoupled.Features.*` | pure modules: `step(state, payload) :: {state, outputs}` functions for `Cart`, `Undo`, `SavedItems`, `Wishlist`, `PageUI`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit` |
| Domain | `ZeroCoupled.Domain.*`, `ZeroCoupled.Cart`, `ZeroCoupled.Catalog.*` | rule functions, the cart aggregate, product badges and buttons |
| Programming paradigms | `ZeroCoupled.Ports.Step`, `ZeroCoupled.Paradigms.*` (no LiveView), `ZeroCoupledWeb.Paradigms.*` | the protocol, `Circuit`, `Adapter`, sources and sinks, `Runner`, `Emitter` |
| Foundation | `ZeroCoupled.Foundation.*` | stores, payment gateway, PubSub wrapper |

## Building block 1: the `Step` port and the circuit

```elixir
defprotocol ZeroCoupled.Ports.Step do
  def push(step, data)   # data is {input, payload}; returns {:emit, [{port, payload}], step} or {:quiet, step}
end

defmodule ZeroCoupled.Paradigms.Circuit do
  defstruct parts: %{}, wires: %{}
  def new(parts), do: %__MODULE__{parts: Map.new(parts)}
  def wire(c, from, to), do: %{c | wires: Map.update(c.wires, from, [to], &(&1 ++ [to]))}

  def push(c, id, data) do
    case Step.push(Map.fetch!(c.parts, id), data) do
      {:quiet, part} -> {put_part(c, id, part), []}
      {:emit, outputs, part} -> Enum.reduce(outputs, {put_part(c, id, part), []}, &route(&1, id, &2))
    end
  end
end
```

An output on a wired port is pushed into each target. An output on an unwired port comes back as the
circuit's **edge**, which is where `:ui` effects end up.

## Building block 2: features through an `Adapter`

Features stay plain modules. `Adapter` makes one into a `Step`, using the input name as the function:
pushing `{:remove, payload}` calls `Cart.remove(state, payload)`. A feature emits on ports that its
docs name.

## Building block 3: sources, transforms and sinks

| Instance | Effect |
|---|---|
| `%FromStore{read: fun}` | emits `loaded: fun.(arg)` |
| `%Via{fun: fun}` | emits `out: fun.(value)` |
| `%ToStream{name}` | stream insert, delete or reset from `{:added \| :changed \| :removed, row}` or `{:reset, rows}` |
| `%ToComponent{module, id}` | `send_update(module, id: id, change: payload)` |
| `%ToAssign{name}` / `%ToAssign{name, value: v}` | assign the payload, or a fixed value |
| `%ToForm{name}` | assign a changeset as a form |
| `%ToFlash{level, text}` / `%ToFlash{level, texts}` | a fixed message, or one keyed by the payload |
| `%ToStore{write: fun}` | call `fun.(value)` |
| `%ToTimer{name, ms, into: {instance, input}}` | on `{:start, payload}`, start a timer that feeds `into`; on `:cancel`, cancel it |
| `%ToPatch{paths}` | `push_patch` to the step's path |
| `%ToAsync{name, fun, ok, error}` | run `fun.(value)` as a task, then feed `{:ok, v}` to `ok` or `{:error, r}` to `error` |
| `%ToRedirect{}` | redirect to the URL |

Each sink is a small struct implementing `Step`. Adding a kind means adding a module.

## Wiring: the page

```elixir
def circuit(cart_id) do
  Circuit.new(
    lines: %FromStore{read: &Carts.list_items/1},
    cart: Adapter.new(Cart, Cart.new(cart_id: cart_id, pricing: @pricing)),
    undo: Adapter.new(Undo, Undo.new([])),
    cart_rows: %ToComponent{module: CartPanel, id: "cart"},
    summary: %ToAssign{name: :summary},
    persist: %ToStore{write: &persist/1},
    undo_clock: %ToTimer{name: :undo, ms: @undo_window_ms, into: {:undo, :expire}},
    add_line: %Via{fun: &add_line(cart_id, &1)},
    restored_notice: %ToFlash{text: "Item restored"},
    charge: %ToAsync{name: :payment, fun: &charge/1, ok: {:checkout, :succeeded}, error: {:checkout, :failed}},
    ...
  )
  |> Circuit.wire({:lines, :loaded}, {:cart, :load})
  |> Circuit.wire({:cart, :rows}, {:cart_rows, :change})
  |> Circuit.wire({:cart, :removed}, {:undo, :capture})
  |> Circuit.wire({:undo, :timer}, {:undo_clock, :value})
  |> Circuit.wire({:undo, :restored}, {:cart, :receive})
  |> Circuit.wire({:undo, :restored}, {:restored_notice, :any})
  |> Circuit.wire({:wishlist, :taken}, {:add_line, :in})
  |> Circuit.wire({:add_line, :out}, {:cart, :receive})
  ...
end
```

The page assigns the circuit in `mount/3` and feeds the first load: `Runner.feed(:lines, {:load,
cart_id})`. Three generic handlers finish the page:

```elixir
def handle_info({:feed, _, _} = message, socket), do: {:noreply, Runner.feed_message(message, socket)}
def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket),
  do: {:noreply, Runner.feed(socket, :cart, {:set_stock, %{product_id: id, stock: stock}})}
def handle_async(_name, result, socket), do: {:noreply, Runner.async_result(result, socket)}
```

Store work that takes more than one call (`add_line`, `charge`, `finalize`) is in private page
functions, which `Via` and `ToAsync` instances wrap.

## UI instances

```elixir
def handle_event("remove_item", %{"item-id" => id}, socket),
  do: {:noreply, Emitter.feed(socket, :cart, {:remove, %{item_id: int(id)}})}

def update(%{change: {:removed, row}}, socket), do: {:ok, stream_delete(socket, :cart_items, row)}
```

`Emitter.feed/3` sends `{:feed, instance, data}` to the page process. Rows come back to the instance
through a `ToComponent` sink, as a `change`. Each instance owns its stream and its events, and names
only the circuit input it feeds.

## Runtime: `Runner`

`Runner.feed/3` pushes into the circuit in assigns, stores the new circuit, and applies each `:ui`
effect on the edge. Effects include stream changes, assigns, flashes, `send_update`, patches, async
tasks, redirects, and named timers. The timer and async messages come back as `{:feed, ...}` and go
into the circuit again.

## Applying it to another project

1. Write each feature as a pure module whose input functions return `{state, outputs}`.
2. Copy `Ports.Step`, `Circuit`, `Adapter`, the sinks and sources, `Runner` and `Emitter`.
3. On each page, write `circuit/1`: name every part, then wire every output. Put the circuit in assigns
   at mount and feed the first load. Add the three generic handlers.
4. Write one LiveComponent per region. Each handles its own events with `Emitter.feed/3` and takes row
   changes in `update/2`.

## Trade-offs and limits

- Two message hops per click, so tests have to settle twice and poll for async results.
- Many parts: the cart circuit names 38 instances and 41 wires, because every flash, assign and stream
  is a named instance.
- Nothing checks that every feature output is wired, and an unwired non-`:ui` output is dropped.
- A sink vocabulary to learn, though each sink is a small module.
- The page holds store helper functions, and the two pages repeat the shipping rates.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/pages/cart_page.ex` | `circuit/1`, mount, the generic handlers, instance placement |
| `lib/zero_coupled/paradigms/circuit.ex` | push and route |
| `lib/zero_coupled/paradigms/sinks.ex` | sources, transforms and sinks |
| `lib/zero_coupled_web/paradigms/runner.ex` | applying `:ui` effects |
| `lib/zero_coupled_web/live/cart_live/instances.ex` | UI instances |
| `test/zero_coupled_web/live/cart_live_test.exs` | `settle/1` and `eventually/3` for the hops |
