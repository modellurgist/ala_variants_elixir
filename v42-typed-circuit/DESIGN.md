# V42 design: typed circuit, sourced from a diagram

A Phoenix LiveView design where each page runs a **circuit**: named instances and the wires from
`{instance, port}` to `{instance, input}`. Every instance, whether a feature, a store-work struct or a
UI sink, implements one protocol, `Ports.Step`. Through that protocol each instance declares **typed
ports** and the inputs it feeds back into later. Each page's circuit is built in its own **diagram
module**, together with the store's literals, as one data expression.

`Circuit.validate!/1` runs at mount and in tests. It refuses:

- a wire to an unknown instance or port;
- a wire between two different types;
- an output that is neither wired nor deliberately grounded;
- a timer or task target that isn't a declared input;
- an anonymous function anywhere in an instance's configuration.

`mix circuit.draw` writes Mermaid drawings from the same value, and its `--check` mode fails when a
committed drawing is stale. Browser events are handled by **UI instances** (LiveComponents), which
push into named circuit inputs.

Use it as the strictest form of the circuit idea. V47 keeps typed, checked, drawable wiring with no
message hops and fewer named instances.

## At a glance

| | |
|---|---|
| Wiring form | a diagram module per page (`CartDiagram.circuit/1`): `Circuit.new(parts)`, then `Circuit.wire/3` and `Circuit.ground/2` |
| Where feature state lives | inside the circuit's parts, in the page's `:circuit` assign |
| Port types | every port declares a paradigm type (`:item`, `:summary`, `:row_change`, `:changeset`, `:any`; `:ui` for runner effects) |
| Runtime | `Circuit` (push, route, validate), `Adapter`, sinks and sources, `Runner`, `Emitter` |
| Store work | domain structs implementing `Step` (`AddLine`, `PlaceOrder`), `FromStore` reads, `ToStore` writes, `ToAsync` for the payment |
| Checks | `Circuit.validate!/1` at mount; `diagrams_test.exs` seeds each kind of mistake; `mix circuit.draw --check` |
| Diagram | `Drawing.mermaid/1` → `docs/diagrams/cart.mmd`, `portal.mmd` |
| Message hops between components | two per click (instance → page → circuit → instance) |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `ZeroCoupledWeb.CartDiagram`, `PortalDiagram`, `Diagrams`, `CartPage`, `PortalPage`, `CartLive.*` and `PortalLive.*` instances | diagram modules (instances, configuration, literals, wires, grounds), pages (mount, generic handlers, template), UI instances |
| State | `ZeroCoupled.Features.*` | pure modules with `ports/0`; `step(state, payload) :: {state, outputs}` functions |
| Domain | `ZeroCoupled.Domain.*`, `ZeroCoupled.Cart`, `ZeroCoupled.Catalog.*` | configured rules (`CalculateShipping.new(rates)`), `AddLine` and `PlaceOrder` (implementing `Step`), the cart aggregate |
| Programming paradigms | `ZeroCoupled.Ports.Step`, `ZeroCoupled.Paradigms.*`, `ZeroCoupledWeb.Paradigms.*` | the protocol, `Circuit`, `Adapter`, the sinks, `Transitions`, `Drawing`, `Runner`, `Emitter`, the `Subscribed` hook |
| Foundation | `ZeroCoupled.Foundation.*` | stores, payment gateway, PubSub wrapper |

## Building block 1: the `Step` port

```elixir
defprotocol ZeroCoupled.Ports.Step do
  @fallback_to_any true
  def push(step, data)   # {input, payload} → {:emit, [{port, payload}], step} | {:quiet, step}
  def ports(step)        # %{in: [name: type], out: [name: type]}
  def feeds(step)        # [{instance, input}] a timer or task pushes into later
end
```

## Building block 2: features with typed ports, through an `Adapter`

```elixir
def ports,
  do: %{
    in: [capture: :item, restore: :event, expire: :item_id],
    out: [captured: :item, timer: :timer, restored: :item, expired: :item_id]
  }
```

Features stay plain modules. `Adapter.new(Undo, Undo.new([]))` makes one a `Step`: the input name is
the function, and `ports/1` reports the module's `ports/0`.

## Building block 3: store work as `Step` instances

```elixir
add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
place_order: %PlaceOrder{orders: Orders, carts: Carts, products: Products,
                         announce: &Broadcast.stock_changed/2, cart_id: cart_id}
```

`AddLine` implements `Step` directly: `push(a, {:add, product})` emits `line:` with the stored line. Its
ports are declared like any other instance's. Every function in a circuit's configuration is a named
capture, so validation can reject closures and the drawing can label each call.

## Building block 4: sinks and sources

The same vocabulary as V40, now with typed ports. `ToStream` and `ToComponent` take `:row_change`,
`ToForm` takes `:changeset`, and `ToAssign`, `ToFlash`, `ToStore`, `ToTimer`, `ToPatch`, `ToAsync` and
`ToRedirect` take their own types. `FromStore` emits `loaded`. Every sink emits on `ui`. `ToTimer` and
`ToAsync` report the inputs they'll feed through `feeds/1`.

## Wiring: the diagram module

```elixir
@rates %{standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000}, ...}
@undo_window_ms 5_000

def circuit(%{cart_id: cart_id, charge: charge}) do
  Circuit.new(
    lines: %FromStore{read: &Carts.list_items/1, type: :items},
    cart: Adapter.new(Cart, Cart.new(cart_id: cart_id, pricing: %{shipping: CalculateShipping.new(@rates), ...})),
    undo: Adapter.new(Undo, Undo.new([])),
    add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
    cart_rows: %ToComponent{module: CartPanel, id: "cart"},
    persist: %ToStore{write: &Carts.apply_change/1},
    undo_clock: %ToTimer{name: :undo, ms: @undo_window_ms, into: {:undo, :expire}},
    restored_notice: %ToFlash{text: "Item restored"},
    charge: %ToAsync{name: :payment, fun: charge, ok: {:checkout, :succeeded}, error: {:checkout, :failed}},
    ...
  )
  |> Circuit.wire({:lines, :loaded}, {:cart, :load})
  |> Circuit.wire({:cart, :removed}, {:undo, :capture})
  |> Circuit.wire({:undo, :timer}, {:undo_clock, :value})
  |> Circuit.wire({:undo, :restored}, {:cart, :receive})
  |> Circuit.wire({:undo, :restored}, {:restored_notice, :show})
  |> Circuit.wire({:wishlist, :taken}, {:add_line, :add})
  |> Circuit.wire({:add_line, :line}, {:cart, :receive})
  |> Circuit.wire({:checkout, :done}, {:place_order, :place})
  |> Circuit.wire({:checkout, :done}, {:go, :url})
  |> Circuit.ground({:add_line, :line_with_quantity})
  |> Circuit.ground({:place_order, :placed})
end
```

The page passes in only what it alone can supply: the cart id, and the payment function, which needs
the page's URLs.

## The page

```elixir
def mount(_params, %{"cart_id" => cart_id}, socket) do
  circuit = Circuit.validate!(CartDiagram.circuit(%{cart_id: cart_id, charge: &charge/1}))
  {:ok, socket |> assign(circuit: circuit, ...) |> Runner.feed(:lines, {:load, cart_id})}
end

def handle_info({:feed, _, _} = message, socket), do: {:noreply, Runner.feed_message(message, socket)}
def handle_info(%Broadcast.Facts.StockChanged{product_id: id, stock: stock}, socket),
  do: {:noreply, Runner.feed(socket, :cart, {:set_stock, %{product_id: id, stock: stock}})}
def handle_info(%Broadcast.Facts.ProductSaved{}, socket), do: {:noreply, socket}
def handle_async(_name, result, socket), do: {:noreply, Runner.async_result(result, socket)}
```

`handle_params` feeds the URL's step to checkout. There's no catch-all `handle_info`. The template
places the UI instances, and each one handles its own events with `Emitter.feed(socket, :cart,
{:remove, ...})`.

## Runtime

`Circuit.push/3` delivers outputs along the wires, depth first. Outputs on unwired ports return as the
edge. `Runner.feed/3` stores the new circuit and applies each `:ui` effect: stream changes, assigns,
flashes, `send_update`, patches, tasks, redirects and named timers. Timers and tasks come back as
`{:feed, instance, data}` messages.

## Checks

- `Circuit.validate!/1` collects wire problems (unknown instance or port, type mismatch), feed problems,
  dangling outputs (neither wired nor grounded, except `:ui`) and anonymous functions, then raises
  with the whole list.
- `test/zero_coupled_web/diagrams_test.exs` validates both diagrams. It seeds each kind of mistake and
  checks it's caught, and it fails if a committed drawing is stale.
- `mix circuit.draw --check` makes the same drawing check from the command line.

## Applying it to another project

1. Give every feature `ports/0` with types. Make multi-step store work into structs that implement
   `Step`.
2. Copy `Ports.Step`, `Circuit` (with `ground/2` and `validate!/1`), `Adapter`, the sinks, `Drawing`,
   `Runner`, `Emitter`, and the `circuit.draw` task.
3. Write one diagram module per page: literals as attributes, `circuit/1` naming every instance, wiring
   every output, and grounding the ones left unused on purpose. Use named captures only.
4. Write each page: validate and assign the circuit at mount, feed the first load, and add the generic
   handlers.
5. Write one LiveComponent per region, feeding named inputs with `Emitter.feed/3`.
6. Add the diagram test and commit the drawings.

## Trade-offs and limits

- Two message hops per click, as in V40.
- Many concepts: circuit, port, port types, grounds, feeds, sinks, runner, UI instances, diagram
  modules. Familiarity 2 of 5.
- Long diagrams, because every flash, assign and stream is a named instance.
- Validation can't see a UI instance's `Emitter.feed` call, so a misspelt input name there shows up
  only when the event fires.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/diagrams/cart_diagram.ex` | the cart page's circuit |
| `lib/zero_coupled_web/pages/cart_page.ex` | mount and the generic handlers |
| `lib/zero_coupled/ports/step.ex` | the port protocol |
| `lib/zero_coupled/paradigms/circuit.ex` | push, route and validation |
| `lib/zero_coupled/paradigms/sinks.ex` | sinks and sources with typed ports |
| `lib/zero_coupled/domain/add_line.ex` | store work as a `Step` instance |
| `test/zero_coupled_web/diagrams_test.exs` | the seeded-mistake tests |
| `docs/diagrams/cart.mmd` | a drawn diagram |
