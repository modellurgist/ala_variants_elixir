# V47 design: typed story maps

A Phoenix LiveView design with Spray's Features layer, where every composition is a **value**. Each page
composes stories (one per user story), and each story's wiring is a **bindings map**: from each of its
parts' output ports, and each of its own input ports, to a list of typed bindings. The page is the root
story; its map says where each story's outputs go. A generic `Binder` runs the composition, and a
`Diagram` module checks the whole thing before the page runs (every port typed, every wire between
matching types, every output bound or deliberately grounded) and draws it as a Mermaid diagram from
the same value that runs. It meets the full [ALA Checklist](https://github.com/modellurgist/ala_checklist).

Use it when you want the wiring to be data you can check, print and draw, and you accept a binding
vocabulary to learn. V46 makes the same split with clauses; V51 with plain functions.

## At a glance

| | |
|---|---|
| Composition layers | the page (application, the root story) and stories (Features) |
| Wiring form | one bindings map per story, and one per page: `%{{source, port} => [binding, ...]}` |
| Where state lives | one `%Binder{}` per story in the page's assigns: module, parts, bindings, view values |
| Runtime | `Binder` (about 190 lines): binding kinds, story inputs, events, timers, tasks |
| Port types | every port declares a type; `Call` instances declare the payload types they accept and answer |
| Checks | `Diagram.check!/1` at mount refuses an unsound composition; tests run the same checks |
| Diagram | `Diagram.mermaid/1` (page) and `Diagram.mermaid_story/2` (one story), from the running value |
| Message hops between components | none |

## Layers

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `ZeroCoupledWeb.Pages.*`, `ZeroCoupledWeb.StoreConfig`, `ZeroCoupledWeb.CartSession` | pages: configuration, `composition/1` building the stories and the page's bindings map, the generic handlers, templates |
| Features | `ZeroCoupledWeb.Stories.*` | `EditCart`, `UndoRemoval`, `SaveForLater`, `KeepWishlist`, `CheckOut`, `EditOrder`, `BrowseCatalog`, `SubmitOrder` |
| State | `ZeroCoupled.State.*` | stateful domain abstractions with typed ports: `Cart`, `Undo`, `SavedItems`, `Wishlist`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit`, `RecordEdit`, `PageUI` |
| Domain | `ZeroCoupled.Domain.*`, `ZeroCoupled.Actions.*`, `ZeroCoupled.Cart`, `ZeroCoupled.Lines` | rule functions, configured store-work instances implementing `Ports.Call` (`AddLine`, `PlaceOrder`, `StartPayment`), the storefront cart aggregate, plain line functions |
| Programming paradigms and foundation | `ZeroCoupledWeb.Paradigms.*`, `ZeroCoupled.Paradigms.*`, `ZeroCoupled.Ports.*`, `ZeroCoupled.Catalog.*`, `ZeroCoupled.Foundation.*` | `Binder`, `Diagram`, the `on_mount` hook, the state-machine table, the `Call` request/response protocol, generic UI components, stores, PubSub wrapper |

## Building block 1: a state module with typed ports

The clause variants' contract: pure functions over the module's own struct, each input returning
`{new_state, [port: payload]}`, and `ports/0` declaring `in` and `out` ports. Here each port's value is
its type (`capture: :item`, `summary: :summary`), and the types are checked. An input typed `:event`
accepts any payload.

## Building block 2: a configured instance behind a `Call` port

Store work (add a line, place an order, start a payment) is a domain struct configured with its stores,
implementing the request/response port:

```elixir
defprotocol ZeroCoupled.Ports.Call do
  def call(instance, payload)
  @doc "The payload types it accepts, each mapped to the type of its answer: `%{product: :item}`."
  def types(instance)
end
```

A binding names the instance itself (`{:via, %AddLine{...}, targets}`), so the wiring never wraps it in
a closure, and its types let the checker match it against the ports on either side.

## Building block 3: a story

A story implements the `Binder` behaviour (`parts/0`, `ports/0`, `events/0`, `streams/0`, `event/4`) and
provides `new/1`, `bindings/n` and view components:

```elixir
defmodule ZeroCoupledWeb.Stories.UndoRemoval do
  use ZeroCoupledWeb, :html
  @behaviour ZeroCoupledWeb.Paradigms.Binder
  alias ZeroCoupled.State.Undo
  alias ZeroCoupledWeb.Paradigms.Binder

  def parts, do: %{undo: Undo}
  def streams, do: []
  def events, do: ["undo_remove"]
  def ports, do: %{in: [capture: :item, expire: :item], out: [restored: :item, expired: :item_id]}

  def new(opts),
    do: Binder.story(__MODULE__, %{undo: Undo.new([])}, bindings(Keyword.fetch!(opts, :window_ms)), pending: false)

  # {source, port} → where it goes in this story; {:in, port} is the story's own input
  def bindings(window_ms) do
    %{
      {:in, :capture} => [{:input, :undo, &Undo.capture/2}],
      {:in, :expire} => [{:input, :undo, &Undo.expire/2}],
      {:undo, :captured} => [{:set, :pending, true}, {:start_timer, :undo, window_ms, :expire}],
      {:undo, :restored} => [{:stop_timer, :undo}, {:set, :pending, false}, {:out, :restored}],
      {:undo, :expired} => [{:set, :pending, false}, {:out, :expired}]
    }
  end

  def event(s, me, "undo_remove", _), do: Binder.run(s, me, :undo, &Undo.restore(&1, nil))

  def view(assigns),
    do: ~H"<.notice shown={@story.view.pending} text={@t.text} action={@t.undo} event=\"undo_remove\" />"
end
```

## The binding kinds

| Binding | Meaning |
|---|---|
| `{:input, part, fun}` | run `fun.(state, payload)` on this story's part, then deliver its outputs |
| `{:out, port}` | send the payload out of this story, to the page's bindings |
| `{:to, story, port}` | (page only) deliver the payload to a story's input port |
| `{:stream, name}` | apply a row change to a LiveView stream |
| `{:show, field}` / `{:set, field, value}` | set a value the story's view shows (an assign, on the page) |
| `{:form, field}` | the payload is a changeset; show it as a form |
| `{:flash, level, text}` / `{:flash_for, level, texts}` | a fixed message, or one chosen by the payload |
| `{:via, callee, targets}` | deliver a `Call` instance's answer to `targets` |
| `{:via, fun, type, targets}` | deliver a plain function's answer, of the declared type, to `targets` |
| `{:call, callee}` | ask the callee for its effect only |
| `{:async, callee, ok, error}` | ask a `Call` instance in a task; the answer arrives at input `ok`, an error or crash at `error` |
| `{:start_timer, name, ms, port}` / `{:stop_timer, name}` | after `ms`, the payload arrives at this story's input `port` |
| `{:patch, paths}` | `push_patch` to the step's path |
| `:redirect` | redirect to the URL in the payload |

## Wiring: the page

The page module builds the composition and mounts it. Its own bindings map is the links between stories:

```elixir
def bindings do
  %{
    {:page, :mounted} => [{:to, :edit_cart, :mounted}, {:to, :check_out, :mounted}],
    {:edit_cart, :summary} => [{:show, :summary}, {:to, :check_out, :summary}],
    {:edit_cart, :removed} => [{:to, :undo, :capture}],
    {:undo, :restored} => [{:to, :edit_cart, :receive}, {:flash, :info, "Item restored"}],
    {:wishlist, :ids} => [{:to, :edit_cart, :wishlist_ids}],
    ...
  }
end

def composition(cart_id) do
  stories = %{
    edit_cart: EditCart.new(cart_id: cart_id, pricing: pricing),
    undo: UndoRemoval.new(window_ms: StoreConfig.undo_window_ms()),
    check_out: CheckOut.new(checkout: [...], start_payment: %StartPayment{...}, place_order: %PlaceOrder{...}),
    ...
  }
  {Binder.story(__MODULE__, %{}, bindings()), stories}
end

def mount(_params, session, socket) do
  cart_id = session[CartSession.cart_key()]
  {:ok, socket |> assign(texts: texts(), ...) |> Binder.mount(composition(cart_id)) |> Binder.send_out(:page, :mounted, cart_id)}
end

def handle_event(name, params, socket), do: {:noreply, Binder.event(socket, @stories, name, params)}
def handle_async({:story_async, _, _, _} = task, result, socket), do: {:noreply, Binder.async_result(socket, task, result)}
def handle_info({:story_input, story, port, payload}, socket), do: {:noreply, Binder.input(socket, story, port, payload)}
```

Loading at mount is itself a binding: `EditCart`'s map binds `{:in, :mounted}` to
`{:via, &Carts.list_items/1, :items, [{:input, :cart, &Cart.load/2}]}`, so the page never holds rows.

## Runtime: `Binder`

`Binder.mount/2` first runs `Diagram.check!/1`, then assigns the page and each story with its streams.
`Binder.run/4` steps a part and delivers each output along the owning story's map; `{:out, port}` hands
the payload to the page's map; `{:to, story, port}` delivers it to a story input. Timers send
`{:story_input, story, port, payload}` back to the page process; tasks are named
`{:story_async, story, ok, error}` and their results go to those inputs. Everything runs in the page's
process.

## Checks

`Diagram.problems/1` returns every problem in a composition, and `check!/1` raises on any:

- a binding from a source that isn't one of the owner's part outputs or own inputs;
- an output neither bound nor listed in `grounded/0`;
- a declared input port with no binding;
- a wire between two different types (an output to an input, a `Call` payload to its answer, a sink to
  the type it shows: a stream takes `:row_change`, a form `:changeset`, a patch `:step`);
- an anonymous function in a binding (it can't be checked or drawn).

Tests call the same checks on each page, and the `Binder` tests show that mount refuses an unsound
composition.

## Applying it to another project

1. Give every state module typed ports, and every configured I/O instance a `Call` implementation with
   `types/1`.
2. Copy `Binder` and `Diagram` (and the `Call` protocol) into your paradigm layer.
3. Write each story: the behaviour callbacks, `new/1` building a `Binder.story`, `bindings/n` for its
   inner wiring and its own inputs, `event/4` clauses, and view components reading `@story.view`.
4. Write each page: `bindings/0` for the links between stories, `composition/1` building the stories,
   `Binder.mount/2` in `mount/3`, and the three generic handlers.
5. List deliberately unbound outputs in `grounded/0`. Run the checks in tests; mount runs them anyway.
6. Draw the diagram with `Diagram.mermaid/1` for reviews and docs.

## Trade-offs and limits

- Familiarity 3: seventeen binding kinds, a typed-port convention, a `Call` protocol and a runtime to
  learn.
- The wiring is data, so it's inspectable and drawn from what runs, but a reader must learn the
  vocabulary before reading a map.
- Store reads use plain function captures with a declared answer type (`{:via, fun, type, targets}`);
  only `Call` instances carry their own types.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/paradigms/binder.ex` | binding kinds and the runtime |
| `lib/zero_coupled_web/paradigms/diagram.ex` | the composition checks and the Mermaid drawer |
| `lib/zero_coupled_web/pages/cart_page.ex` | a page's bindings and composition |
| `lib/zero_coupled_web/stories/` | the eight stories |
| `lib/zero_coupled/ports/call.ex` | the request/response port |
| `test/zero_coupled_web/paradigms/binder_test.exs` | mount refusing an unsound composition, and the binding kinds |
