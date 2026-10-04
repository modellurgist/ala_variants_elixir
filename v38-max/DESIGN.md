# V38-max design: one plain LiveView that only wires

A Phoenix LiveView design where each page is **one plain LiveView module**. It has no LiveComponents,
no bindings map, no route table and no runtime beyond a 56-line helper. Every feature is a pure state
value in the page's assigns. Each browser event runs one feature step, and `Steps.run/4` folds each
output through the page's private `wire/3`, **one clause per declared port**. Those clauses are the
page's wiring, read top to bottom. There are no message hops.

Use it when your team wants the most ordinary LiveView shape that still keeps logic out of the page.
V48 and V50 take the same `wire/3` form further. V45 adds named instances and a compile-time check.

## At a glance

| | |
|---|---|
| Wiring form | private `wire(socket, feature_key, {port, payload})` clauses on the page, one per declared port |
| Where feature state lives | page assigns, one per feature (`:cart`, `:undo`, `:checkout`, ...) |
| Runtime | `Steps` (56 lines): `run/4`, `feed/6`, `stream_change/3`, `patch/3`, `start_timer/4`, `stop_timer/2` |
| Store work | configured domain structs kept in assigns (`add_line`, `charge`, `settle`), called from `wire/3` clauses; the payment runs as a `start_async` task |
| Coverage check | a test reads each page's `wire/3` heads and checks them against every declared port, both ways |
| Layer check | a custom Credo check (`AlaLayerBoundary`) flags references into forbidden layers by directory |
| Diagram | none |
| Message hops between components | none |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `GoodDealWeb.CartLive.Show`, `PortalLive.Show`, `ProductLive.*`, `GoodDeal.Catalog`, `CartSession`, `CheckoutMetadata` | pages (configuration, `features/0`, handlers, `wire/3`, templates), the store's calibration, two named contracts (the session key, the payment metadata key) |
| State | `GoodDeal.Features.*` | pure stateful modules with declared ports: `Cart`, `Undo`, `SavedItems`, `Wishlist`, `PageUI`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit` |
| Domain | `GoodDeal.Domain.*`, `GoodDeal.Actions.*`, `GoodDeal.Cart` | configured rule structs, store-work structs (`AddLine`, `Charge`, `SettleOrder`, `PlaceOrder`), the cart aggregate |
| Programming paradigms and foundation | `GoodDealWeb.Paradigms.*`, `GoodDeal.Paradigms.*`, `GoodDeal.Components.*`, `GoodDeal.Foundation.*` | `Steps`, the `Subscribed` `on_mount` hook, the state-machine table, generic UI components (rows, panes, parts), stores, payment gateway, PubSub wrapper |

The state modules live under a `Features` namespace, but they're state abstractions, not Spray's
Features layer of user stories. In a new project, call the namespace `State`.

`GoodDeal.Catalog` holds the store's calibration: shipping rates, promo codes, gift-wrap price, volume
tiers, the low-stock level, the undo window, currency, and shared words. Pages read it and pass its
values down. No domain or state module reaches up to it.

## Building block 1: a state module with ports

Each state module is a set of pure functions over its own struct. Each input returns
`{new_state, [port: payload]}`, and `ports/0` declares `in` and `out`. Outputs state facts
(`captured`, `restored`, `ready_to_pay`). Configuration comes in through `new/1`. A state module does
no I/O and names no peer module.

## Building block 2: a configured store-work struct

Multi-step store work is a domain struct configured with the stores it uses. The page builds one in
`mount/3` and keeps it in assigns:

```elixir
add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
charge: %Charge{gateway: Application.get_env(:good_deal, :payment_gateway, LedgerGateway),
                metadata: &CheckoutMetadata.for_cart/1},
settle: %SettleOrder{orders: Orders, carts: Carts, products: Products,
                     announce: &Broadcast.stock_changed/2, cart_id: cart_id}
```

## Wiring: the page

Each handler decodes its params and runs one feature input:

```elixir
def handle_event("remove_item", %{"item-id" => id}, socket),
  do: {:noreply, run(socket, :cart, &Cart.remove(&1, %{item_id: int(id)}))}

def handle_info({:timer, :undo, %{id: id}}, socket), do: {:noreply, run(socket, :undo, &Undo.expire(&1, id))}

defp run(socket, key, step), do: Steps.run(socket, key, step, &wire/3)
```

Each output goes through one `wire/3` clause:

```elixir
defp wire(s, :cart, {:rows, change}), do: Steps.stream_change(s, :cart_items, change)
defp wire(s, :cart, {:summary, summary}), do: assign(s, :summary, summary)
defp wire(s, :cart, {:changed, change}), do: (Carts.apply_change(change); s)
defp wire(s, :cart, {:removed, item}), do: run(s, :undo, &Undo.capture(&1, item))
defp wire(s, :cart, {:checkout_requested, cart}), do: run(s, :checkout, &Checkout.pay(&1, cart))

defp wire(s, :undo, {:captured, item}),
  do: s |> assign(:undo_pending, true) |> Steps.start_timer(:undo, item, Catalog.undo_window_ms())

defp wire(s, :undo, {:restored, item}),
  do: s |> Steps.stop_timer(:undo) |> assign(:undo_pending, false)
        |> run(:cart, &Cart.receive(&1, item)) |> put_flash(:info, "Item restored")

defp wire(s, :wishlist, {:taken, product}),
  do: s |> Steps.feed(:cart, &Cart.receive/2, &AddLine.run(s.assigns.add_line, &1), product, &wire/3)
        |> put_flash(:info, "Added to cart")

defp wire(s, :checkout, {:step, step}), do: s |> assign(:step, step) |> Steps.patch(@step_paths, step)

defp wire(s, :checkout, {:ready_to_pay, payment}),
  do: start_async(s, :payment, fn -> Charge.call(s.assigns.charge, payment) end)

defp wire(s, :checkout, {:done, reference}) do
  SettleOrder.run(s.assigns.settle, reference)
  push_navigate(s, to: ~p"/cart/success")
end
```

A clause runs another feature (`run`), lands a value (`assign`, a stream change, `put_flash`,
`patch`), or calls a store or configured instance. It never decides anything. `feed/6` asks a source
for a value and runs a feature input with the answer, so a clause never nests one call inside another.
There's no catch-all clause.

`mount/3` builds the configuration and each feature, assigns them with the view values and empty
streams, then loads the cart through `Steps.feed(:cart, &Cart.load/2, &Carts.list_items/1, cart_id,
&wire/3)`. `features/0` maps each key to its state module for the coverage test. The page's templates
are its own `render/1` clauses, which place generic components.

## Runtime: `Steps`

```elixir
def run(socket, key, step, wire) do
  {state, outputs} = step.(socket.assigns[key])
  Enum.reduce(outputs, assign(socket, key, state), &wire.(&2, key, &1))
end

def feed(socket, key, input, source, payload, wire),
  do: run(socket, key, &input.(&1, ask(source, payload)), wire)
```

The rest of `Steps` holds small LiveView helpers: `stream_change/3` (from `{:reset | :removed | _,
row}`), `patch/3` (to a step's path when it has one), and named timers kept in a `:timers` assign.

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** all go to the page, and each runs one feature input.
- **URL steps:** checkout outputs `step`, and its clause patches through `@step_paths`. `handle_params`
  asks checkout to `goto` the URL's step, and the feature decides whether to honour it.
- **Timers:** `Steps.start_timer/4` and `stop_timer/2` in Undo's clauses. `handle_info({:timer, ...})`
  runs `Undo.expire`.
- **Store I/O:** the cart loads through `feed`, the `changed` clause writes, and `AddLine` and
  `SettleOrder` run synchronously in clauses. The payment runs as a `start_async` task, and the page's
  `handle_async` clauses feed the result back to checkout.
- **PubSub:** an `on_mount` hook subscribes the page. Stock changes run `Cart.set_stock`, and catalogue
  edits get explicit empty clauses.

## UI

`GoodDeal.Components` holds generic parts. `Rows` take event names and words as attributes. `Panes` has
`pane`, `only_on`, `tabs` and `stream_list`. `Parts` has `notice`, `none`, `primary_button`,
`cart_summary`, `shipping_selector` and `promo_form`. Every word comes from the page's `texts`, merged
with the store's shared words from `Catalog`.

## Checks

- `WiringTest` parses each page's source, collects every `defp wire(_, key, {port, _})` head, and
  checks two things: every out port of every feature in `features/0` has a clause, and every clause
  names a declared port.
- `.credo.exs` configures `Credo.Check.Custom.AlaLayerBoundary`, which maps each layer's directory to
  module prefixes that files there must not reference. For example, `lib/good_deal/domain/` may not
  reference `GoodDeal.Foundation`, `GoodDealWeb` or `Phoenix`.

## Applying it to another project

1. Write each feature as a pure state module with `ports/0` and `new/1`.
2. Make multi-step store work into configured domain structs.
3. Copy `Steps` into your paradigm layer.
4. On each page, build the configuration and features in `mount/3`. Write one-line handlers that call
   `run/3`, and one `wire/3` clause per declared port. Add `features/0`.
5. Put the store's calibration in one application-layer module that pages read.
6. Add the clause-head coverage test. Optionally, add the Credo layer check with your own directory map.

## Trade-offs and limits

- The page module is large (the cart page is about 480 lines with its templates), because events,
  wiring and markup all sit in it.
- All feature state sits in one LiveView's assigns.
- No diagram is drawn from the clauses (V48 and V50 add one).
- Store work in clauses runs synchronously in the page process, apart from the payment.
- Familiarity 4: nothing beyond LiveView, apart from a few `Steps` helpers.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/good_deal_web/live/cart_live/show.ex` | configuration, handlers, `wire/3` clauses and templates |
| `lib/good_deal_web/paradigms/steps.ex` | the runtime |
| `lib/good_deal/catalog.ex` | the store's calibration |
| `lib/good_deal/domain/settle_order.ex` | a configured store-work struct |
| `test/good_deal_web/live/wiring_test.exs` | the clause-head coverage test |
| `lib/good_deal/credo/ala_layer_boundary.ex` and `.credo.exs` | the layer boundary check |
