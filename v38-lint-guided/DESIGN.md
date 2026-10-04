# V38 design: a disciplined conventional LiveView, moved toward ALA by the linter

This is not a wiring design. V38 is a conventional Phoenix LiveView app: each page is one LiveView
module that holds its logic in its event handlers. Over five iterations, the linter's findings moved it
partway toward ALA, and the changes were kept small and familiar. Three disciplines hold it together:

- **Domain modules are pure and generic.** They take every store-specific number as an argument.
- **The store's calibration lives in one application-layer module**, `GoodDeal.Catalog`. The page reads
  it and passes its values down.
- **Each handler computes the new state and then lists its side effects as data.** One private
  `apply_effects/2` carries the effects out.

Use this design as a starting point, or as a baseline to measure an ALA design against. V38-max shows
what the same app becomes when the page only wires.

## At a glance

| | |
|---|---|
| Wiring form | none as such: each `handle_event` computes the new state, then returns an effect list |
| Where state lives | page assigns, as plain structs: `CartState`, `UIState`, `CheckoutState` (cart page), `OrderState` (portal) |
| Logic | in the page's handlers and in `CartState.recompute/1`, calling pure domain functions |
| Side effects | effect tuples (`{:flash, ...}`, `{:patch, path}`, `{:stream_insert, ...}`, `{:persist_remove, ...}`, `{:start_checkout, ...}`) applied by a private `apply_effect/2` |
| Calibration | `GoodDeal.Catalog`: shipping methods, gift-wrap price, promo codes, volume tiers, low-stock threshold |
| Layer check | a custom Credo check, `AlaLayerBoundary`, configured in `.credo.exs` |
| Message hops | none |

## Layers

The layer map that `ala_lint` was given:

| Layer | Namespace | What lives there |
|---|---|---|
| Application | `GoodDealWeb.CartLive.Show`, `PortalLive.Show`, `ProductLive.*`, `GoodDeal.Catalog`, `CartSession`, `CheckoutMetadata` | pages with their logic and templates, the store's calibration, two named contracts |
| Feature (page state) | `GoodDealWeb.CartLive.CartState`, `UIState`, `CheckoutState`, `Helpers`, `PortalLive.OrderState` | the page's state structs, totals recomputed from domain functions, list helpers |
| Domain | `GoodDeal.Domain.*` (`Pricing`, `Shipping`, `Inventory`, `Checkout`, `VolumeTier`, `Forms`), `GoodDeal.Actions.SaveProduct` | pure functions with calibration as arguments |
| Foundation | `GoodDeal.Foundation.*` | Ecto stores, schemas, payment gateway, PubSub wrapper |

## Building block 1: generic domain functions

Each domain module is a set of pure functions. They take the store's numbers as arguments, so nothing
below the application layer holds a product literal:

```elixir
def validate_promo(code, codes) when is_binary(code) and is_map(codes) do
  case Map.get(codes, String.upcase(String.trim(code))) do
    nil -> {:error, :invalid_code}
    pct -> {:ok, pct}
  end
end

def stock_status(stock, _threshold) when stock <= 0, do: :out_of_stock
def stock_status(stock, threshold) when stock <= threshold, do: :low_stock
def stock_status(_stock, _threshold), do: :in_stock
```

## Building block 2: calibration at the top

```elixir
defmodule GoodDeal.Catalog do
  def shipping_methods, do: [...]
  def gift_wrap_cents, do: 299
  def promo_codes, do: %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}
  def low_stock_threshold, do: 5
end
```

The page passes these values into state (`CartState.new(cart_id, items, store_calibration())`) and into
domain calls (`Pricing.validate_promo(code, Catalog.promo_codes())`). No lower module calls `Catalog`.

## Building block 3: a page state struct with derived totals

`CartState` holds the items, promo, shipping choice and gift-wrapped ids, plus the calibration it was
built with. `recompute/1` derives the subtotal, discount, shipping, gift wrap, total and item count from
domain functions. The handlers call it after every change.

## The page

Each handler reads state, decides, builds the new state, and lists its effects:

```elixir
def handle_event("undo_remove", _params, socket) do
  case socket.assigns.ui.undo do
    nil ->
      {:noreply, socket}

    %{item: item, ref: ref} ->
      cart = CartState.recompute(%{socket.assigns.cart | items: socket.assigns.cart.items ++ [item]})
      ui = %{socket.assigns.ui | undo: nil}

      effects = [
        {:cancel_timer, ref},
        {:stream_insert, :cart_items, Helpers.row(item, cart, wishlist_ids(socket))},
        {:flash, :info, "Item restored"}
      ]

      {:noreply, socket |> assign(cart: cart, ui: ui) |> apply_effects(effects)}
  end
end

defp apply_effect(socket, {:flash, level, msg}), do: put_flash(socket, level, msg)
defp apply_effect(socket, {:patch, path}), do: push_patch(socket, to: path)
defp apply_effect(socket, {:persist_remove, cart_id, item_id}) do
  Carts.remove_item(cart_id, item_id)
  socket
end
```

Payment validation, stock checks, the undo window, step changes and order finalisation are all
handled in the page module's handlers and private functions. The cart page's templates and private
components sit in the same module, which is about 850 lines.

## Events, URLs, timers, async, store I/O and PubSub

- **Browser events:** all go to the page.
- **URL steps:** handlers patch through `@step_paths`. `handle_params` lets the URL go back from
  payment to address and ignores any other jump.
- **Timers:** `remove_item` starts `Process.send_after` for the undo window and keeps the ref in
  `UIState`. A later removal cancels the earlier timer and makes that removal final.
- **Store I/O:** reads happen in `mount/3` and handlers. Writes happen through effects. The payment
  runs as a `start_async` task, and `handle_async` finalises the order.
- **PubSub:** `mount/3` subscribes when connected. A catch-all `handle_info` ignores unknown messages.
- **Contracts:** `CartSession` owns the session key, and `CheckoutMetadata` owns the payment metadata
  key, so neither is a bare string agreed on in two places.

## Checks

- `ala_lint` runs with a layer map for this project. Its findings drove the iterations: hoisting
  calibration (R3), single-sourcing contracts (R5), and keeping no upward or peer calls (R1).
- `.credo.exs` configures `AlaLayerBoundary`, which maps each layer's directory to module prefixes that
  files there must not reference. It also lists a `V27CrossFeatureCoupling` check whose module isn't in
  this repo.
- Unit tests cover the domain modules and `Helpers`. LiveView tests cover the pages.

## Applying it to another project

This design is a set of moves on an existing conventional LiveView app, not a structure to copy:

1. Declare a layer map (application, feature, domain, foundation) and run `ala_lint` with it. Fix any
   upward or peer call first.
2. Move every store-specific number out of domain modules into one application-layer calibration
   module. Make the domain functions take the numbers as arguments.
3. Give every string that two modules must agree on (session keys, metadata keys) one owning module.
4. Have handlers list their side effects as data, and apply the list in one place.
5. Add a Credo layer-boundary check so new code can't reach across layers.
6. To keep going, move the decisions out of the handlers into pure state modules with ports, and make
   the page only wire, as V38-max does.

## Trade-offs and limits

- The page decides things. Handlers branch on state, validate, and finalise orders, so the page is
  both the application layer and the feature logic (R11).
- The page module is large and holds logic, wiring and markup together.
- The effect list is an internal convention, so nothing checks that every effect is handled.
- It's the most familiar shape here: nothing to learn beyond LiveView.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/good_deal_web/live/cart_live/show.ex` | handlers, effects and templates |
| `lib/good_deal_web/live/cart_live/cart_state.ex` | state with derived totals |
| `lib/good_deal/catalog.ex` | the store's calibration |
| `lib/good_deal/domain/pricing.ex` | a generic domain module |
| `lib/good_deal_web/cart_session.ex`, `checkout_metadata.ex` | single-sourced contracts |
| `README.md` | the iteration log, with the linter scores at each step |
