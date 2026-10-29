# V59: light ALA (form 1c with composition roots)

Light ALA is the subset of Spray's Abstraction Layered Architecture that cost about what
conventional Phoenix costs when seven variants of this store went through the same ten
requirement changes. It keeps the layering, calibration at the top, rules as named pure modules,
configuration passed down in structs, guards in the writer and one composition root per page.
It drops ports and wiring, so pages still call their parts and pass values along as V0's do. This
is a reading of the ALA checklist, not Spray's ALA, which also composes by ports. V59 is V58
(`../v58-layered-v0-roots`, hybrid 1) with the two guards that hybrid 1's change run showed it
needed. Behaviour is V58's except on one stale-session path (below). [DESIGN.md](DESIGN.md) has
each rule with an example from this code, the layer map, the roots, the guard audit and what
changed from V58.

## The twelve rules

Each line names the V0 habit it replaces.

1. Dependencies point down four layers: app, contexts, domain, platform. Replaces `Orders` calling `Catalog` and `ShoppingCart.Pricing`.
2. Every application literal lives in `GoodDealWeb.Calibration` and travels down in a struct. Replaces module attributes such as `Catalog`'s `@low_stock_threshold`.
3. A business rule is a named pure module configured by its caller. Replaces rules buried in context functions (`Catalog.stock_status/1`).
4. Everything else stays V0: contexts, LiveViews, streams, PubSub, `start_async`, Mox. Replaces nothing.
5. Configuration and session values pass once, as `%Channel{}` and `%Shop{}`. Replaces context functions taking a bare `cart_id` and growing positional arguments.
6. A rule grows by a field or a function, never by a reshaped return. Replaces renaming a key when a value splits.
7. Tests sit at the page and the context; a rule has unit tests only for its edge cases. Keeps V0's placement.
8. A value the domain needs is an enforced key, not a default. Replaces defaults that hide a missing value.
9. A guard lives in the context function that writes the data and refuses with a tagged error. Replaces checks that only a page makes.
10. Each page builds its parts in one `parts/…` called from `mount`. Replaces handlers reading the session, calibration or app env themselves.
11. Every builder of a config or context struct takes its required values plus keyword overrides, and tests build only through builders. Replaces struct literals in tests and positional builders.
12. A write to a session cart sees a current cart: the page checks the cart is open before each event and reloads through the session plug if not, and every cart writer refuses a closed cart. Replaces V0's events writing to the cart id captured at mount.

## Reading a page

Start at its `parts/…` function. It says which channel the page sells on, how it prices a cart,
how removal is undone and which session cart it writes to. The cart page and the portal compose
`CartSession.editor_parts/4`, so their root is one call naming the channel, the stream and the
reprice function, and the parts it returns are listed in that function. `mount` assigns the parts once and
attaches the open-cart guard. Handlers then call `parts.shop`, `parts.pricing.(cart)` and
`parts.undo` and do the rest as V0 would. A handler never calls `Calibration` or `CartSession`.
Below the page, read the context function it calls, then the domain rule that function or the
pricing hands a channel to.

## Status (2026-10-24)

175 tests, 0 failures, three runs in a row (V58's 151 plus 24 for the two guards).
No behavioural assertion changed; test edits are builder calls only. `mix compile
--warnings-as-errors`, `mix format --check-formatted` and `mix credo` (353 mods/funs, no issues)
are clean. `mix test --cover` totals 99.61% with V0's ignores. `ala_lint` scores 100 at normal,
strict and super-strict through `lint.exs`, with V58's settings and layer map, and no `ala:accept`
lines. It reports no clone, and R7 is met under `--strict`, where V58's last clone left it unmet.
Production code is 3,129 lines (`lib/**/*.ex`) against V58's 3,054; tests are 2,353 lines
against 2,062.

Toolchain as V0 (`.tool-versions`). Databases `good_deal_v59_dev` and `good_deal_v59_test`.

## What it costs and what it buys

Over ten changes form 1c used 1.07 times V0's tokens, broke 19 previous-step tests against V0's 33
and scored 4.3 for design fit against V0's 4.0. Hybrid 1's roots added 49 production lines over
those ten changes and let a reader learn a page's setup from one function
(`ala_lab/docs/change-cost-form1-2026-10-24.md`). The two guards here close the two problems that
run found: a reorder event that wrote into a completed cart, and a positional shop builder whose
new argument broke 119 tests through the shared fixture. Neither guard has been through the change
sequence yet, so their cost over ten changes is unmeasured.

## Run

```sh
mix setup        # deps, DB good_deal_v59_dev, migrations, seeds, assets
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

- `GoodDealWeb.Calibration`: every §7 value and the store's other literals, as one `%Channel{}` per channel (`channel(:storefront | :portal, overrides \\ [])`; tests pass overrides), plus `pricing/3`, which configures `Domain.Pricing` for a channel and a cart, and `undo_window_ms/0`.
- `GoodDeal.Channel` and `GoodDeal.Shop` (platform): the configuration struct and the session struct. Each page's `parts/1` builds its shop with `CartSession.session_shop/2`; `EnsureCart` builds one per session key with `CartSession.shop(channel, cart_id: id)`.
- `GoodDeal.Domain.{Pricing, ShippingMethod, VolumeTier, PromoCode, StockStatus}`: pure rules taking a `%Channel{}` (or `%Pricing{}` / `%ShippingMethod{}`) and a value.
- `GoodDeal.Catalog`: products. `GoodDeal.ProductEvents` (platform) owns the PubSub topic (`{:product_created | :product_updated | :product_deleted, product}`); Catalog and Orders both publish there.
- `GoodDeal.ShoppingCart`: carts (open/completed/abandoned, promo code, shipping method, embedded address), items (quantity, gift wrap, saved for later), wishlist. Every writer of cart contents refuses a cart that is no longer open with `{:error, :cart_closed}`.
- `GoodDeal.Orders`: orders with line items, storefront checkout (decrements stock) and portal submit (PO number). The page passes in the shop and the price summary, which carries the items it priced.
- `GoodDeal.Payments`: provider behaviour, configured with `config :good_deal, :payment_provider`; `InProcessProvider` is the default, Mox in tests.
- `GoodDealWeb.Plugs.EnsureCart` + `GoodDealWeb.CartSession`: session keys `"cart_id"` and `"portal_cart_id"`, defined once in `CartSession`. Each page builds its own shop in its root, and `CartSession.guard_open_cart/4` reloads a page whose session cart closed before an event writes to it.
- LiveViews: `ProductLive` (generated), `CartLive.Index`, `CheckoutLive.Index`/`Success`, `PortalLive.Index`; `GoodDealWeb.UndoRemoval` is the shared deferred-removal helper, configured per page as `%UndoRemoval{stream:, window_ms:, shop:, reprice:}`. The cart page and the portal both build their parts with `CartSession.editor_parts(session, channel, stream, reprice)`.

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
- **A cart closed elsewhere** (ordered in another tab, say, while this page still holds its id from mount): the page's next event does nothing, flashes "That cart is closed, so nothing changed. Please try again." and reloads with a full request, which gives it the session's current open cart. V58 wrote such events into the closed cart, where nothing read them again. On the product list only Add to cart is checked; staff edits and deletes go through.
- No browser tests. Client-only behaviour (spinner animation, `data-confirm`, CSS-hidden tabs) is checked only as rendered HTML.
