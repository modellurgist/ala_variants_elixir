# V41: Feature components

The same storefront and B2B portal as V39 and V40 (the V35 requirements), in the shape
`phx.gen.live` produces: each feature is a **LiveComponent instance** that owns its state,
stream, buttons and store writes; the page's template places and configures the instances, and
its `handle_info` clauses pass each instance's announcement on to the instance it concerns and say
what happened. The real-size build of toy T24.

**Score:** `ala_lint` 98/A default, 97/A strict, 97/A super-strict on the family layer map
(V39: 97/97/96; V40: 98/97/96; V35: 93/93/91; re-scored 2026-09-29). No R1 finding, no R11 finding on either page.
**80 tests, 0 failures.**

## The shape

- **Features** (`lib/zero_coupled/features/*.ex`) are V39/V40's pure modules, unchanged:
  `step(state, payload) :: {state, [{port, payload}]}`.
- **Each feature has a `Panel`** (`lib/zero_coupled/features/cart/panel.ex`, `undo/banner.ex`,
  ...), a LiveComponent in the same feature unit. A panel: is configured by attributes
  (`cart_id`, `pricing`, the texts it shows); loads its own rows from the store on first
  `update/2`; handles its own events with `phx-target={@myself}`; runs a feature step with
  `Instance.step/3` and lands each output in `land/2` (a stream insert, an assign, a store write);
  and **announces** any output it does not land, as `{name, port, payload}` to the process that
  mounted it. Inputs from outside arrive by `send_update` (`receive: item`, `set_stock: change`).
- **`ZeroCoupledWeb.Paradigms.Instance`** (18 lines) is all the machinery: `step/3` and
  `announce/3`. There is no Binder, no circuit, no protocol.
- **The page** (`lib/zero_coupled_web/pages/cart_page.ex`, 233 lines with its template; the
  portal 147) has: calibration as attributes; `mount/3` that assigns configuration; one
  `handle_params` that records the URL's step; two `handle_event`s (tabs, the checkout button);
  and ~20 `handle_info` clauses of the form

  ```elixir
  def handle_info({:undo, :restored, item}, socket),
    do: {:noreply, socket |> pass(Cart.Panel, "cart", receive: item) |> put_flash(:info, "Item restored")}
  ```

  plus `patch/3`, which moves the URL when a flow announces a step. Every flash text is here.
- **Rows** (`ZeroCoupled.Catalog.Rows`) moved down to the catalog domain: generic row markup
  that takes its event names and target as attributes, used by six panels.

## What it settles that the toy could not

- **Feature logic stays pure.** Because the panels reuse the pure feature modules, nothing that
  decides anything lives in a LiveComponent; the panels only land outputs. T24 had the logic in
  the component; at nine features that would have been the "logic trapped in LiveView" the old
  scorecard penalises.
- **Hops.** A panel's own action (quantity, remove, promo, shipping, address form, pay) renders
  synchronously, with no hop; only a cross-feature effect takes two messages (panel → page →
  panel). V40 paid two hops for everything. The tests still `settle/1` with two renders after an
  action that crosses features.
- **URL patching cannot happen inside `update/2`** (LiveView raises), so a flow panel announces
  `{:checkout, :step, step}` and the page patches. That put the step-to-path table where the
  calibration already was, which is where the checklist wants it.
- **`send_update` to an unmounted instance raises**, so the cart page keeps its index
  instances mounted (hidden) behind the checkout screen, and the portal keeps its lines and
  catalog mounted behind the review. Nothing announced while paying is lost, and back-navigation
  is instant; the cost is a hidden subtree.
- **Reading the design.** The map of who announces what, and where it goes, is the page's
  `handle_info` clauses plus each panel's `@moduledoc`. It reads as requirements, one line per
  wire, but it is not one table (R8 by hand: a point below V39).

## Running

```bash
mix deps.get
mix test
mix phx.server   # http://localhost:4000/cart and /portal
```

## Known departures and judgement calls

- The two pages' shipping rates repeat (R5), as in V39/V40; also the instance id `"undo"`.
- `StockStatus`'s threshold and V35's product pages are untouched, as before.
- `Checkout.Panel` and `PortalSubmit.Panel` place the order themselves (`Orders.create`, stock
  decrement, broadcast): the instance that owns the flow owns its completion. In V39 that was a
  page wire.
- The R3 text check does not scan `~H` sigils, so the prose inside panels ("Processing
  payment…", "Payment failed.", "Full name") is invisible to the linter. Texts the page should own
  are passed in (`empty_text`, `invalid_promo_text`, the banner `text`, every flash); the screen
  labels stayed in the panels as a judgement call.
