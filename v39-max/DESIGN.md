# V39-max design: bound ports

A Phoenix LiveView design where every feature is a pure state value in the page's assigns, and each
page's wiring is **one bindings map**. The map's keys are `{feature, port}` pairs, and each value is a
list of bindings: where that port's output goes. An output might feed another feature's input, fill a
stream or an assign, flash a message, start a timer, patch the URL, call a store, or start a task. A
generic `Binder` runs a feature step and delivers each output along the map. Everything runs in the
page process, so there are no message hops between features. The same map value draws the page's
diagram.

Use it when you want a page's whole wiring in one value that you can test and draw, and you accept a
binding vocabulary to learn. V47 grows the same idea into typed, checked story maps. V45, V48 and V50
write the wiring as plain function clauses.

## At a glance

| | |
|---|---|
| Wiring form | `bindings/1` on each page: `%{{feature, port} => [binding, ...]}` |
| Where feature state lives | page assigns, one per feature (`:cart`, `:undo`, `:checkout`, ...) |
| Runtime | `Binder` (about 120 lines): `run/4`, `deliver/4`, fourteen binding kinds |
| Store work | configured domain instances implementing the `Ports.Call` protocol, named directly in bindings |
| Coverage check | a test checks every declared output is bound or listed in `grounded/0`, and every binding key names a declared port |
| Diagram | `Drawing.mermaid/1`, drawn from `bindings/1` |
| Message hops between components | none |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `ZeroCoupledWeb.CartPage`, `PortalPage`, `CartLive.*View`, `PortalLive.PortalView`, `ProductLive.*`, `StoreConfig`, `CartSession` | pages (configuration, `bindings/1`, `features/0`, `grounded/0`, handlers that decode events into feature inputs), and view modules that place parts |
| State | `ZeroCoupled.Features.*` | pure stateful modules with declared ports: `Cart` (the aggregate's feature functions), `Undo`, `SavedItems`, `Wishlist`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit`, and `PageUI` for tabs |
| Domain | `ZeroCoupled.Domain.*`, `ZeroCoupled.Actions.*`, `ZeroCoupled.Cart` | configured rule structs, store-work structs implementing `Ports.Call` (`AddLine`, `PlaceOrder`, `StartPayment`), the cart aggregate |
| Programming paradigms and foundation | `ZeroCoupledWeb.Paradigms.*`, `ZeroCoupled.Paradigms.*`, `ZeroCoupled.Ports.Call`, `ZeroCoupled.Catalog.*`, `ZeroCoupled.Foundation.*` | `Binder`, `Drawing`, the `Subscribed` `on_mount` hook, the state-machine table, the request/response protocol, generic UI parts, stores, PubSub wrapper |

The state modules live under a `Features` namespace, but they're state abstractions, not Spray's
Features layer of user stories. In a new project, call the namespace `State`.

## Building block 1: a state module with ports

Each state module is a set of pure functions over its own struct. Each input returns
`{new_state, [port: payload]}`, and `ports/0` declares the `in` and `out` ports. Outputs state facts
(`captured`, `restored`, `ready_to_pay`). A state module does no I/O and names no peer module.
Configuration comes in through `new/1`:

```elixir
Checkout.new(
  flow: @checkout_flow,
  start: :address,
  url_edges: @checkout_url_edges,
  stock_levels: &Products.stock_levels/1,
  line_items: BuildLineItems.new(currency: StoreConfig.currency()),
  messages: %{postal_code: "must be 4–10 digits"}
)
```

## Building block 2: a configured instance behind the `Call` port

```elixir
defprotocol ZeroCoupled.Ports.Call do
  def call(instance, payload)
end
```

Store work that takes more than one call (adding a line, placing an order, starting a payment) is a
domain struct configured with its stores and implementing `Call`. A binding names the struct itself,
`{:via, %AddLine{carts: Carts, products: Products, cart_id: id}, targets}`, so the wiring never wraps it
in a closure. A plain function of the payload, or of nothing, works as a callee too.

## Wiring: the page

```elixir
def bindings(cart_id) do
  %{
    {:page, :mounted} => [
      {:via, &Carts.list_items/1, [{:input, :cart, &Cart.load/2}]},
      {:input, :checkout, &Checkout.show_form/2}
    ],
    {:cart, :rows} => [{:stream, :cart_items}],
    {:cart, :summary} => [{:assign, :summary}],
    {:cart, :changed} => [{:call, &Carts.apply_change/1}],
    {:cart, :removed} => [{:input, :undo, &Undo.capture/2}],
    {:undo, :captured} => [{:set, :undo_pending, true}, {:start_timer, :undo, StoreConfig.undo_window_ms()}],
    {:undo, :restored} => [
      {:stop_timer, :undo},
      {:input, :cart, &Cart.receive/2},
      {:flash, :info, "Item restored"},
      {:set, :undo_pending, false}
    ],
    {:wishlist, :taken} => [
      {:via, %AddLine{carts: Carts, products: Products, cart_id: cart_id},
       [{:input, :cart, &Cart.receive/2}, {:flash, :info, "Added to cart"}]}
    ],
    {:checkout, :step} => [{:assign, :step}, {:patch, @step_paths}],
    {:checkout, :form} => [{:form, :address_form}],
    {:checkout, :blocked} => [{:flash_for, :error, @blocked}],
    {:checkout, :ready_to_pay} => [{:async, :payment, %StartPayment{...}}],
    {:checkout, :done} => [{:call, %PlaceOrder{...}}, :redirect]
  }
end

def grounded, do: []
def features, do: %{cart: Cart, undo: Undo, saved: SavedItems, wishlist: Wishlist, ui: PageUI, checkout: Checkout}
```

`mount/3` assigns the bindings, each feature's initial state, the view values and empty streams. It
then delivers `{:page, :mounted}` as if the page were a feature, so loading the cart is a binding too:

```elixir
socket
|> assign(bindings: bindings(cart_id), cart: ZeroCoupled.Cart.new(...), undo: Undo.new([]), ...)
|> stream(:cart_items, [])
|> Binder.deliver(bindings(cart_id), :page, mounted: cart_id)
```

Each handler decodes its input and runs one feature input. The handlers don't hold any logic:

```elixir
def handle_event("remove_item", %{"item-id" => id}, socket),
  do: {:noreply, run(socket, :cart, &Cart.remove(&1, %{item_id: int(id)}))}

def handle_info({:timer, :undo, %{id: id}}, socket), do: {:noreply, run(socket, :undo, &Undo.expire(&1, id))}

def handle_async(:payment, {:ok, {:ok, url}}, socket),
  do: {:noreply, run(socket, :checkout, &Checkout.succeeded(&1, url))}

defp run(socket, key, step), do: Binder.run(socket, socket.assigns.bindings, key, step)
```

`render/1` hands off to a view module per screen (`IndexView`, `CheckoutView`). The view modules place
generic parts and read the assigns that bindings fill.

## The binding kinds

| Binding | Meaning |
|---|---|
| `{:input, key, fun}` | run `fun.(state, payload)` on feature `key`, then deliver its outputs |
| `{:stream, name}` | `{:added \| :changed, row}` inserts, `{:removed, row}` deletes, `{:reset, rows}` resets |
| `{:assign, name}` / `{:set, name, value}` | the payload, or a fixed value, becomes an assign |
| `{:form, name}` | the payload is a changeset; assign it as a form |
| `{:flash, level, text}` / `{:flash_for, level, texts}` | a fixed message, or the one keyed by the payload |
| `{:via, callee, targets}` | deliver the callee's answer to `targets` |
| `{:call, callee}` | ask the callee for its effect only |
| `{:async, name, callee}` | ask the callee in a `start_async` task named `name` |
| `{:start_timer, name, ms}` / `{:stop_timer, name}` | send `{:timer, name, payload}` to the page after `ms`, replacing a running one; or cancel it |
| `{:patch, paths}` | `push_patch` to `paths[payload]`, when the step has a path |
| `:redirect` | redirect to the URL in the payload |

## Runtime: `Binder`

```elixir
def run(socket, bindings, key, step) do
  {state, outputs} = step.(socket.assigns[key])
  deliver(assign(socket, key, state), bindings, key, outputs)
end

def deliver(socket, bindings, key, outputs) do
  Enum.reduce(outputs, socket, fn {port, payload}, socket ->
    bindings |> Map.get({key, port}, []) |> Enum.reduce(socket, &apply_binding(&1, payload, bindings, &2))
  end)
end
```

An `{:input, ...}` binding calls `run/4` again, so a chain of features runs to the end within one
event. A port with no binding is silently dropped at runtime, which is why the coverage test exists.
Timer refs are kept in a `:timers` assign.

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** all go to the page. Each `handle_event` decodes params and runs one feature input.
- **URL steps:** checkout outputs `step`, and its bindings assign it and patch through `@step_paths`.
  `handle_params` asks checkout to `goto` the URL's step, and the feature decides whether to honour it.
- **Timers:** `start_timer`/`stop_timer` bindings on Undo's `captured`/`restored` facts. The page's
  `handle_info({:timer, :undo, item})` runs `Undo.expire`.
- **Store I/O:** reads are `via` bindings on plain functions. Writes are `call` bindings. Multi-step work
  goes through `Call` instances, and the payment runs as an `async` binding whose results reach checkout
  through `handle_async`.
- **PubSub:** an `on_mount` hook subscribes the page. `handle_info` runs a feature input for each fact
  the page uses.
- **Product forms** are the `phx.gen.live` form component.

## UI

`ZeroCoupled.Catalog` holds generic parts. `Rows` take event names and words as attributes. `Panes` has
`pane`, `only_on` and `tabs`. `Parts` has `notice`, `none` and `stream_list`, which hold the template
comparisons so the view modules only place parts. Every word comes from the page's `texts`.

## Checks

`WiringTest`, for each page:

- every out port of every feature in `features/0` is a key in `bindings/1` or listed in `grounded/0`;
- every binding key (other than `:page`) names a port its feature declares.

`DrawingTest` checks that known edges appear in the drawn diagram.

## Applying it to another project

1. Write each feature as a pure state module with `ports/0` and `new/1` for its configuration.
2. Make multi-step store work into configured structs implementing a `Call` protocol.
3. Copy `Binder`, `Drawing` and the `Call` protocol into your paradigm layer.
4. On each page, write `bindings/1`, `features/0` and `grounded/0`. In `mount/3`, assign the bindings,
   the feature states and the streams, then deliver `{:page, :mounted}`. Write handlers that decode
   input and call `Binder.run/4` once.
5. Put markup in view modules that place generic parts.
6. Add the bound-or-grounded test, and draw the map for reviews.

## Trade-offs and limits

- Familiarity 3: fourteen binding kinds and a protocol to learn before the map reads easily.
- A typo in a binding key or a missing binding drops the output silently at runtime. Only the test
  catches it, and there are no port types.
- The page module holds both the map and every event decoder, so it grows with the page: the cart page
  is about 330 lines.
- All feature state sits in one LiveView's assigns, so any re-render diffs against the whole page.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/pages/cart_page.ex` | `bindings/1`, configuration and handlers |
| `lib/zero_coupled_web/paradigms/binder.ex` | the binding kinds and the runtime |
| `lib/zero_coupled_web/paradigms/drawing.ex` | the Mermaid drawer |
| `lib/zero_coupled/ports/call.ex` and `lib/zero_coupled/domain/add_line.ex` | the request/response port and an instance of it |
| `lib/zero_coupled_web/live/cart_live/index_view.ex` | a view that only places parts |
| `test/zero_coupled_web/pages/wiring_test.exs` | the coverage and drawing tests |
