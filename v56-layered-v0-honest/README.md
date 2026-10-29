# V56: layered V0 with stable, honest interfaces (ALA form 1c)

V55 (`../v55-layered-v0-stable`, ALA form 1b) with two rules added to its seven. A value the
domain needs is an enforced key of its struct, not a default (rule 8), and a rule that guards data
is checked by the context function that writes the data (rule 9). Form 1b's change-cost run showed
that some of its low breakage came from contracts no test checked. These two rules put those
checks back. Behaviour is V55's. Like V55, this is a checklist reading, not Spray's ALA, whose
core also composes by ports. [DESIGN.md](DESIGN.md) has the nine rules, the structs with their
enforced and defaulted fields, the guard audit, and what changed from V55.

**Status (2026-10-24).** 149 tests, 0 failures, three runs in a row (V55's 146 plus 3 context
tests for guards now enforced in `Orders` and in the cart item schema). Existing tests changed only
in setup or in a call, never in an assertion: the three rule tests build their channel through a
fixture, the status test calls `set_cart_status/2`, and the stock-rollback test saves an address
first.
`mix compile --warnings-as-errors`, `mix format --check-formatted` and `mix credo` (333 mods/funs,
no issues) are clean. `mix test --cover` totals 99.58% (V55: 99.58%) with V0's ignores. `ala_lint`
scores 100 at normal, strict and super-strict through `lint.exs`, with V55's check settings.
Production code is 2,994 lines (`lib/**/*.ex`) against V55's 2,974; tests are 2,068 lines against
1,996.

Toolchain as V0 (`.tool-versions`). Databases `good_deal_v56_dev` and `good_deal_v56_test`.

## Run

```sh
mix setup        # deps, DB good_deal_v56_dev, migrations, seeds, assets
mix phx.server   # http://localhost:4000/products, /cart, /portal
```

Postgres on localhost, `postgres`/`postgres`.

## Tests

```sh
mix test                                 # everything
mix test test/good_deal                  # context, domain rule and schema unit tests
mix test test/good_deal_web/plugs        # session cart plug
mix test test/good_deal_web/controllers  # generated controller/error tests
mix test test/good_deal_web/live         # LiveView tests
mix test --cover                         # coverage (boilerplate ignored, see mix.exs)
```

The undo window is 5 s in `config/config.exs` and 1 s in `config/test.exs`. Most tests trigger expiry
by sending `{:undo_expired, item_id}` to the LiveView; one test per page waits for the real timer.

## Layout

- `GoodDealWeb.Calibration`: every §7 value and the store's other literals, as one `%Channel{}` per channel (`channel(:storefront | :portal)`), plus `pricing/2`, which configures `Domain.Pricing` for a channel and a cart.
- `GoodDeal.Channel` and `GoodDeal.Shop` (platform): the configuration struct and the session struct. `CartSession` builds a storefront `shop` and a `portal_shop` per LiveView; `EnsureCart` builds one per session key.
- `GoodDeal.Domain.{Pricing, ShippingMethod, VolumeTier, PromoCode, StockStatus}`: pure rules taking a `%Channel{}` (or `%Pricing{}` / `%ShippingMethod{}`) and a value.
- `GoodDeal.Catalog`: products. `GoodDeal.ProductEvents` (platform) owns the PubSub topic (`{:product_created | :product_updated | :product_deleted, product}`); Catalog and Orders both publish there.
- `GoodDeal.ShoppingCart`: carts (open/completed/abandoned, promo code, shipping method, embedded address), items (quantity, gift wrap, saved for later), wishlist.
- `GoodDeal.Orders`: orders with line items, storefront checkout (decrements stock) and portal submit (PO number). The page passes in the shop and the price summary, which carries the items it priced.
- `GoodDeal.Payments`: provider behaviour, configured with `config :good_deal, :payment_provider`; `InProcessProvider` is the default, Mox in tests.
- `GoodDealWeb.Plugs.EnsureCart` + `GoodDealWeb.CartSession` (`on_mount`): session keys `"cart_id"` and `"portal_cart_id"`, defined once in `CartSession`.
- LiveViews: `ProductLive` (generated), `CartLive.Index`, `CheckoutLive.Index`/`Success`, `PortalLive.Index`; `GoodDealWeb.UndoRemoval` is the shared deferred-removal helper.

## Requirement traceability

| Req | Test file | Test |
|---|---|---|
| R1.1 | plugs/ensure_cart_test.exs | first visit stores new open carts…; a completed cart is replaced by a new empty one |
| R1.2 | plugs/ensure_cart_test.exs | first visit stores new open carts for the storefront and the portal |
| R1.3 | good_deal/shopping_cart_test.exs | a new cart is open, on the channel's default shipping method; status is one of open, completed, abandoned (`set_cart_status/2`) |
| R1.3 | live/checkout_live_test.exs | processes asynchronously, creates the order, completes the cart… |
| R1.4 | plugs/ensure_cart_test.exs | an open cart in the session is kept, with its items |
| R1.4 | live/cart_live_test.exs | items persist across page loads with the same cart |
| R2.1 | live/product_live_test.exs | lists name, description, price, thumbnail and stock |
| R2.2 | live/product_live_test.exs | saves new product; updates product in listing; deletes product in listing; updates product within modal; submitting an invalid form keeps the modal open with errors |
| R2.2 | good_deal/catalog_test.exs | only name and amount are required |
| R2.3 | live/product_live_test.exs | displays product |
| R2.4 | live/product_live_test.exs | add to cart persists a line in the session cart |
| R2.5 | live/product_live_test.exs | products saved elsewhere appear and update in every open list |
| R2.6 | live/product_live_test.exs | a stock change shows in every open list |
| R2.6 | live/checkout_live_test.exs | processes asynchronously… (open product list shows the decrement) |
| R3.1 | live/cart_live_test.exs | shows each item's name, thumbnail, prices, quantity and stock status; gift wrap adds 299… |
| R3.1 | live/product_live_test.exs, good_deal/domain/stock_status_test.exs | stock shows as low at 5 and in stock at 6; out at zero or below, low up to the threshold, in stock above |
| R3.2 | live/cart_live_test.exs | increment and decrement change quantity, totals and persist |
| R3.3 | live/cart_live_test.exs | removing hides the row, recomputes totals and shows the undo banner |
| R3.4 | live/cart_live_test.exs | gift wrap adds 299 per wrapped item…; undo restores the item, flashes, recomputes and clears its gift wrap |
| R3.5 | live/cart_live_test.exs | an empty cart says so and disables checkout |
| R3.6 | good_deal/shopping_cart_test.exs | add_item/3 adds a line; adding again increments the same line |
| R3.6 | live/product_live_test.exs | add to cart persists a line in the session cart |
| R3.7 | live/cart_live_test.exs | each tab shows its count and switching is UI state only |
| R3.8 | live/cart_live_test.exs | save for later moves an item to Saved and back; saving the same item twice keeps one saved entry |
| R3.9 | live/cart_live_test.exs | toggle a cart item's product in and out of the wishlist; remove a product from the wishlist; add to cart from the wishlist… |
| R3.10 | live/cart_live_test.exs | shows item count, subtotal, shipping and total; a valid promo flashes and shows the discount |
| R3.11 | live/cart_live_test.exs | shows item count, subtotal, shipping and total; each promo code takes its own percentage off the subtotal; the total is subtotal less discount plus gift wrap plus shipping; gift wrap adds 299… |
| R3.12 | live/cart_live_test.exs | a valid promo flashes…; an invalid promo flashes, shows the error inline and changes nothing |
| R3.13 | live/cart_live_test.exs | choosing a shipping method updates the cost and persists; standard shipping is free above the threshold; an empty cart says so… (Free) |
| R3.13 | live/cart_live_test.exs, good_deal/domain/shipping_method_test.exs | standard shipping is free at exactly 5,000 and charged at 4,999; costs its flat rate, waived from free_above; an empty cart ships free |
| R3.14 | live/cart_live_test.exs | a stock change updates the row in every open cart; saved and wishlisted rows update too |
| R4.1 | live/cart_live_test.exs, live/portal_live_test.exs | removing hides the row…; removing a line arms the undo banner… |
| R4.2 | live/cart_live_test.exs, live/portal_live_test.exs | undo restores the item, flashes…; removing a line arms the undo banner; undo restores and reprices |
| R4.3 | live/cart_live_test.exs | when the window elapses the removal is persisted…; the undo window is a real timer; a stale expiry does not touch the current removal |
| R4.3 | live/portal_live_test.exs | the elapsed window persists the removal |
| R4.4 | live/cart_live_test.exs, live/portal_live_test.exs | a second removal makes the first final…; only the latest removal is undoable |
| R5.1 | live/cart_live_test.exs | starts checkout; with an empty cart flashes and stays |
| R5.2 | live/checkout_live_test.exs | shows the milestones with Address current; validates required fields live and on submit; a valid address advances to payment |
| R5.3 | live/checkout_live_test.exs | shows the address summary, the total, Edit address and Pay; Edit address goes back… |
| R5.4 | live/checkout_live_test.exs | checks for an empty cart; checks stock for every item; processes asynchronously… |
| R5.5 | live/checkout_live_test.exs | processes asynchronously, creates the order, completes the cart, decrements and broadcasts stock; a failed payment shows Payment failed. and a retry…; a crashing provider counts as a failed payment; the success page thanks the shopper |
| R5.5 | good_deal/orders_test.exs | complete_checkout/2 … (including: refuses a cart with no address, an empty summary, or another cart's items) |
| R5.6 | live/checkout_live_test.exs | back is honoured and a forward jump is ignored; loading the payment URL without an address…; reloading the payment URL lands on payment |
| R5.7 | live/checkout_live_test.exs | the default provider settles in-process and returns the shop's success URL |
| R5.7 | good_deal/payments_test.exs | (both tests) |
| R6.1 | live/portal_live_test.exs | lists the catalog with stock status…; adding sets the requested quantity and repeat adds accumulate; the added quantity is at least 1 |
| R6.2 | live/portal_live_test.exs | lines show name, stock status, quantity and line total; changing quantity persists and reprices |
| R6.3 | live/portal_live_test.exs | describe "removal and undo" (all) |
| R6.4 | live/portal_live_test.exs | volume pricing applies by tier and reprices across boundaries |
| R6.4 | live/portal_live_test.exs, good_deal/domain/volume_tier_test.exs | the 5% tier starts at exactly 50,000; picks the highest tier the subtotal reaches; no tiers, no discount |
| R6.5 | live/portal_live_test.exs | shipping methods are the storefront's |
| R6.6 | live/portal_live_test.exs | reviewing an empty order flashes and stays; review shows totals and a live-validated PO form…; an invalid PO stays on review |
| R6.7 | live/portal_live_test.exs | a valid PO completes the draft, creates the order and lands on Submitted |
| R6.7 | good_deal/orders_test.exs | submit_portal_order/3 … (including: refuses another cart's items) |
| R6.8 | live/portal_live_test.exs | stock changes update the catalog row and the affected order line |
| R6.9 | live/portal_live_test.exs | describe "step URLs" (all) |
| R8.1 | live/*_live_test.exs | every list is a stream; catalog and lines are streams; the broadcast tests above (R2.5, R2.6, R3.14, R6.8) |
| R8.2 | good_deal/*_test.exs | all context tests run against Postgres through Ecto |

## Choices and deviations

- **Deferred removal.** The removed item stays in the database until the window elapses (or another removal, an add in the portal, checkout, or review replaces it). If the shopper leaves the page during the window, the LiveView process ends and the removal is never persisted: the item is still in the cart next time.
- **Removal clears gift wrap** when the item is restored (R3.4); while pending it is excluded from totals anyway.
- **Checkout address is persisted on the cart** (embedded schema) so a reload of `/cart/checkout/payment` can land on payment (R5.6). Loading the payment URL with no saved address goes to the address step.
- **Payment provider** (R5.7): `create_checkout_session(line_items, success_url: url)` returns `{:ok, url}`. After `{:ok, url}` the LiveView creates the order, completes the cart, decrements stock and does a full `redirect(external: url)`. The full redirect makes the session plug start a new cart. If stock ran out while paying, the order is not created and the page shows "Some items are out of stock" (payment is not refunded; there is no real provider).
- **Portal submit does not decrement stock**, following R6.7 as written (listed as an open question in the requirements).
- **Portal has no promo codes or gift wrap** (R6.5 as built).
- **`abandoned`** is a valid cart status but nothing sets it (as built).
- **Success page** only says thanks; it shows no order (as built).
- **Back from Submitted** is ignored: the draft is completed. Reaching the portal again by live navigation re-mounts with the old session, so the page does a full redirect to `/portal` to get a new draft.
- **Tabs and portal steps** hide panels with CSS rather than removing them, because a stream container that leaves the DOM loses its items.
- Calibration lives in `GoodDealWeb.Calibration` as one `%Channel{}` per channel (shipping methods, default shipping method, promo codes, gift wrap, volume tiers, low-stock threshold, postal-code length, PO number format and message) and app config (undo window, payment provider), as in V0. The portal's channel has no promo codes and a gift-wrap price of 0; the storefront's has no volume tiers.
- **Coverage**: `mix.exs` `test_coverage.ignore_modules` drops generated boilerplate (Application, Repo, CoreComponents, Layouts, PageHTML, ErrorHTML, Telemetry) and test support. What remains uncovered is the generated, unused `pipeline :api` in the router and a function the framework generates at `ProductLive.FormComponent`'s `defmodule` line.
- No browser tests. Client-only behaviour (spinner animation, `data-confirm`, CSS-hidden tabs) is checked only as rendered HTML.
