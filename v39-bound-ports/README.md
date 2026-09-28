# V39: Bound ports

The storefront and the B2B portal (the same requirements as V35: cart, tabs, save for later,
wishlist, promo, shipping, gift wrap, undo with a window, a checkout flow with async payment,
live stock, a bulk-order draft with volume tiers and a PO form), rebuilt so that each page's
whole design is one map: `bindings/1`.

**Score:** `ala_lint` 97/A default, 97/A strict, 96/A super-strict on the family layer map
(V35: 93/93/91; all re-scored 2026-09-29). **83 tests, 0 failures.**

## The shape

- **Features** (`lib/zero_coupled/features/`) are plain functions over a private struct:
  `step(state, payload) :: {state, [{port, payload}]}`. A feature names its output *ports*
  (`:rows`, `:summary`, `:removed`, `:persist`, `:timer`, `:step`, `:blocked`, ...) and never a
  stream, an assign, a flash text, a URL, or another feature. Nine of them: Cart, Undo,
  SavedItems, Wishlist, PageUI, Checkout, OrderLines, PortalCatalog, PortalSubmit. Cart and
  OrderLines are two features over the same `ZeroCoupled.Cart` aggregate (kept from V35).
- **The page** (`lib/zero_coupled_web/pages/cart_page.ex`, `portal_page.ex`) has a
  `bindings/1` map from `{feature, port}` to where that port lands on this page. Every handler
  is one line: `run(socket, :cart, &Cart.remove(&1, %{item_id: id}))`. The store's literals
  (pricing, promo codes, the undo window, the flow tables, every message) sit in the page as
  attributes.
- **The Binder** (`lib/zero_coupled_web/paradigms/binder.ex`, 111 lines) runs a step and delivers
  its outputs along the bindings. Binding kinds: `{:stream, name}` (incl. `:reset`),
  `{:assign, name}`, `{:set, name, value}`, `{:form, name}`, `{:flash, level, text}`,
  `{:flash_for, level, texts}`, `{:input, key, fun}` (another feature's input),
  `{:via, fun, targets}` (a page function, then more bindings), `{:call, fun}`,
  `{:timer, name, ms}`, `{:patch, paths}`, `{:async, name, fun}`, `:redirect`.
- **Rows** (`lib/zero_coupled_web/components/rows.ex`) render the projected row shapes and take
  the event names they fire as attributes, so the same row serves any page.

A reader can state the requirements from `bindings/1` plus the attributes above it: what each
feature emits and where it goes, with the store's numbers and words next to it.

## Composed inputs

Where a feature needs another's data, the page composes it in the handler, in one line:
`Wishlist.toggle(&1, Cart.find(socket.assigns.cart, id))`; `Checkout.pay(&1, %{cart: cart,
stock: Products.stock_levels(ids)})`. The linter's handles-data detector accepts these because
the values go straight into one feature input.

## What folding in T20 (codegen from the bindings) would add

Not done here, on purpose. The toy T20 generated wiring clauses from a bindings map and checked
them in CI (`mix toy.gen --check`). Folding that into V39 would give:

1. **A drift check.** Today nothing verifies that every port a feature emits has a binding, or
   that every binding names a port the feature really emits. An unbound port is silently
   dropped (`Map.get(bindings, {key, port}, [])`). A generator that reads the feature modules'
   port docs (or a `ports/0` function on each) and diffs them against `bindings/1` would turn a
   forgotten binding into a build failure. This is the D6 vocabulary drift T17 showed and T20
   removed.
2. **Handlers as data.** The 30-odd one-line `handle_event`/`handle_info` clauses are the same
   shape every time: event name, params to a payload, feature and function. A table
   `%{"remove_item" => {:cart, &Cart.remove/2, item_id: :int}}` would let the generator emit the
   clauses, making the page a map of bindings and a map of events, nothing else. The page's
   public surface (the linter counts 29 functions on `CartPage`) would shrink to what LiveView
   requires.
3. **A diagram artifact.** The bindings map is already a graph; a generator could emit it as a
   Mermaid diagram for the README, keeping the picture and the code from drifting.

The cost, seen in T20: a generator to maintain (about 150 lines), generated files to commit and
review, and a new way for a change to be "done" (edit the map, run the generator) that every
contributor must learn. On V30 the same trade bought a checked seam; on V39 the Binder already
runs the map directly, so the generator would only add the *check*, not the *wiring*. That is why
it stayed out: V39 wants to show how far the map alone goes.

## Running

```bash
mix deps.get
mix test
mix phx.server   # http://localhost:4000/cart and /portal
```

Postgres is expected at `localhost:5432` (see `config/dev.exs` and `config/test.exs`).

## Known departures and judgement calls

- The stock subscription is an `on_mount` hook (`ZeroCoupledWeb.Paradigms.Subscribed`,
  configured on each page), so neither `mount/3` branches; and `Carts.apply_change/1` takes the
  cart's persist port directly, so the pages have no `persist/2`. Both backported from toys
  T22/T23 after the first build.
- The three shipping rates appear in both pages' attributes (the linter's R5 finding). They are
  two stores' calibration that happen to agree today; a shared attribute module would be one
  edit away, and would also be a shared literal two pages depend on.
- `StockStatus` keeps its low-stock threshold of 5 inside the domain rule, as V35 built it.
- The product pages (`ProductLive.*`) are V35's, untouched, and carry V35's findings.
