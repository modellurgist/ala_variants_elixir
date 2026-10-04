# V39 design: bound ports

A Phoenix LiveView design where every feature is a pure state value in the page's assigns, and each
page's wiring is **one bindings map**. The map's keys are `{feature, port}` pairs, and each value is a
list of bindings: where that port's output goes. An output might feed another feature's input, fill a
stream or an assign, flash a message, start a timer, patch the URL, call a function, or start a task. A
generic `Binder` runs a feature step and delivers each output along the map, all within the page
process, so there are no message hops.

This is the first version of the design. V39-max adds declared ports, a coverage test, configured
store-work instances in place of page helpers, mount as a binding, and a diagram drawer.

## At a glance

| | |
|---|---|
| Wiring form | `bindings/1` on each page: `%{{feature, port} => [binding, ...]}` |
| Where feature state lives | page assigns, one per feature (`:cart`, `:undo`, `:checkout`, ...) |
| Runtime | `Binder` (111 lines): `run/4`, `deliver/4`, thirteen binding kinds |
| Store work | private page helpers (`add_line/2`, `charge/1`, `finalize/2`) named in `via`, `call` and `async` bindings |
| Coverage check | none: an unbound port is dropped silently |
| Diagram | none |
| Message hops between components | none |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `ZeroCoupledWeb.CartPage`, `PortalPage`, `CartLive.*View`, `PortalLive.PortalView`, `ProductLive.*` | pages (configuration as module attributes, `bindings/1`, handlers, store helpers), and view modules |
| State | `ZeroCoupled.Features.*` | pure stateful modules: `Cart`, `Undo`, `SavedItems`, `Wishlist`, `PageUI`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit` |
| Domain | `ZeroCoupled.Domain.*`, `ZeroCoupled.Cart`, `ZeroCoupled.Catalog.*` | rule functions, the cart aggregate (two features, `Cart` and `OrderLines`, run over it), product badges and buttons |
| Programming paradigms and foundation | `ZeroCoupledWeb.Paradigms.*`, `ZeroCoupled.Paradigms.*`, `ZeroCoupledWeb.Components.Rows`, `ZeroCoupled.Foundation.*` | `Binder`, the `Subscribed` `on_mount` hook, the state-machine table, generic rows, stores, PubSub wrapper |

The state modules live under a `Features` namespace, but they're state abstractions, not Spray's
Features layer of user stories. In a new project, call the namespace `State`.

## Building block: a state module with ports

Each state module is a set of pure functions over a private struct. Each input returns
`{new_state, [port: payload]}`. A state module names its output ports (`:rows`, `:summary`, `:removed`,
`:persist`, `:timer`, `:step`) and never a stream, an assign, a flash text, a URL, or another feature.
The ports are listed in the `@moduledoc`, not in a function:

```elixir
def capture(%__MODULE__{} = undo, item),
  do: {%{undo | pending: item}, [captured: item, timer: {:start, item.id}]}

def restore(%__MODULE__{pending: item} = undo, _),
  do: {%{undo | pending: nil}, [restored: item, timer: :cancel]}
```

`Undo` asks for a clock through its `:timer` port, and whoever binds the port picks the window's
length.

## Wiring: the page

```elixir
def bindings(cart_id) do
  %{
    {:cart, :rows} => [{:stream, :cart_items}],
    {:cart, :summary} => [{:assign, :summary}],
    {:cart, :persist} => [{:call, &Carts.apply_change/1}],
    {:cart, :removed} => [{:input, :undo, &Undo.capture/2}],
    {:undo, :captured} => [{:set, :undo_pending, true}],
    {:undo, :timer} => [{:timer, :undo, @undo_window_ms}],
    {:undo, :restored} => [{:input, :cart, &Cart.receive/2}, {:flash, :info, "Item restored"}, {:set, :undo_pending, false}],
    {:wishlist, :taken} => [
      {:via, &add_line(cart_id, &1), [{:input, :cart, &Cart.receive/2}, {:flash, :info, "Added to cart"}]}
    ],
    {:checkout, :step} => [{:assign, :step}, {:patch, @step_paths}],
    {:checkout, :form} => [{:form, :address_form}],
    {:checkout, :payment} => [{:async, :payment, &charge/1}],
    {:checkout, :done} => [{:via, &finalize(cart_id, &1), [:redirect]}]
  }
end
```

`mount/3` loads the cart from the store, builds each feature, and assigns the bindings, the feature
states, the view values and the streams. Each handler is one line that runs one feature input:

```elixir
def handle_event("remove_item", %{"item-id" => id}, socket),
  do: {:noreply, run(socket, :cart, &Cart.remove(&1, %{item_id: int(id)}))}

def handle_info({:timer, :undo, item_id}, socket), do: {:noreply, run(socket, :undo, &Undo.expire(&1, item_id))}

defp run(socket, key, step), do: Binder.run(socket, socket.assigns.bindings, key, step)
```

Some handlers compose a feature's input from another feature's state or from a store read:

```elixir
def handle_event("toggle_wishlist", %{"item-id" => id}, socket),
  do: {:noreply, run(socket, :wishlist, &Wishlist.toggle(&1, Cart.find(socket.assigns.cart, int(id))))}

def handle_event("pay", _params, socket) do
  cart = socket.assigns.cart
  stock = Products.stock_levels(Enum.map(Cart.items(cart), & &1.product.id))
  {:noreply, run(socket, :checkout, &Checkout.pay(&1, %{cart: cart, stock: stock}))}
end
```

Store work that takes more than one call lives in private page functions: `add_line/2`, `charge/1`
(the payment gateway) and `finalize/2` (create the order, drop stock, broadcast). The bindings name
these functions. `render/1` hands off to a view module per screen.

## The binding kinds

| Binding | Meaning |
|---|---|
| `{:input, key, fun}` | run `fun.(state, payload)` on feature `key`, then deliver its outputs |
| `{:stream, name}` | insert, delete or reset stream rows from `{:added \| :changed \| :removed, row}` or `{:reset, rows}` |
| `{:assign, name}` / `{:set, name, value}` | the payload, or a fixed value, becomes an assign |
| `{:form, name}` | the payload is a changeset; assign it as a form |
| `{:flash, level, text}` / `{:flash_for, level, texts}` | a fixed message, or the one keyed by the payload |
| `{:via, fun, targets}` | deliver `fun.(payload)` to `targets` |
| `{:call, fun}` | call `fun.(payload)` for its effect |
| `{:timer, name, ms}` | on `{:start, payload}`, send `{:timer, name, payload}` after `ms`; on `:cancel`, cancel it |
| `{:patch, paths}` | `push_patch` to `paths[payload]`, when the step has a path |
| `{:async, name, fun}` | run `fun.(payload)` in a `start_async` task |
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

An `{:input, ...}` binding runs another step, so a chain of features finishes within one event.

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** all go to the page. Each handler decodes params and runs one feature input.
- **URL steps:** checkout outputs `step`, and its bindings patch through `@step_paths`. `handle_params`
  asks checkout to `goto` the URL's step, and the feature decides whether to honour it.
- **Timers:** a `{:timer, name, ms}` binding on a feature's `:timer` port. The page's
  `handle_info({:timer, ...})` runs the feature's expiry input.
- **Store I/O:** the initial load happens in `mount/3`. Writes go through `call` and `via` bindings on
  store functions or page helpers, and the payment through an `async` binding.
- **PubSub:** an `on_mount` hook subscribes the page. `handle_info` runs `Cart.set_stock` for stock
  facts, and a catch-all clause ignores everything else.

## Applying it to another project

1. Write each feature as a pure state module whose inputs return `{state, [port: payload]}`.
2. Copy `Binder` into your paradigm layer.
3. On each page, write `bindings/1`. Build the features in `mount/3` and assign them with the bindings.
   Write one-line handlers that call `Binder.run/4`.
4. Put multi-step store work in functions the bindings name. V39-max shows how to move these into
   configured domain instances.
5. Put markup in view modules that read the assigns the bindings fill.

## Trade-offs and limits

- Nothing checks the map against the features. A missing binding or a typo in a port name drops the
  output silently, and the catch-all `handle_info` hides unhandled messages.
- The page holds store helpers and composes some inputs from feature state, so it knows more than wiring.
- The two pages repeat the shipping rates.
- Familiarity: thirteen binding kinds to learn before the map reads easily.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/pages/cart_page.ex` | `bindings/1`, handlers and store helpers |
| `lib/zero_coupled_web/paradigms/binder.ex` | the binding kinds and the runtime |
| `lib/zero_coupled/features/undo.ex` | a feature that asks for a timer through a port |
| `lib/zero_coupled_web/live/cart_live/index_view.ex` | a view module |
| `test/zero_coupled_web/paradigms/binder_test.exs` | the binding kinds |
