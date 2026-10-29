# V55 design: layered V0 with stable interfaces (ALA form 1b)

Form 1 (V54) ran the six-step change sequence at V0's cost but broke 1.44 times as many existing
tests as V0. The reviewer traced the excess to interfaces: calibration accessors renamed when a
value split by channel, context functions growing positional arguments as calibration and session
values were passed down, rule functions reshaped instead of extended, and unit tests pinned to rule
shapes (`ala_lab/docs/change-cost-form1-2026-10-24.md`). V55 is V54 changed as little as possible
to fix those four things. Behaviour is V54's.

## The seven rules

Form 1's four, unchanged:

1. **Dependencies point down (R1).** Four layers, below. Contexts may not call each other, and
   neither may domain rules.
2. **Calibration at the top (R3).** Every application literal lives in `GoodDealWeb.Calibration`
   and reaches lower layers inside a configuration struct. No context or domain module holds a §7
   value or a channel name.
3. **Rules as named pure modules (R6, R7).** A rule is a module named for its concept, configured
   by its caller, with no I/O. One-line calls stay where they are.
4. **Everything else is V0.** Contexts, LiveViews, streams, PubSub, `start_async`, Mox. Pages
   branch, loop and pass values between calls as V0's do.

Three about interfaces:

5. **Configuration is passed once, as a struct.** A channel's calibration is one `%Channel{}`. A
   page's session values travel in one `%Shop{}`, which carries the channel. A context function
   that needs either takes the shop as its first argument; a rule takes the channel (or the
   narrower struct it is configured by) as its first argument. A new input later is a new field
   with a default, not a new parameter, and a value that may one day differ by channel is already
   a field of the channel, so splitting it changes a value, not a name.
6. **Rules are extended, not reshaped.** A rule's public functions take the configuration struct
   and a value and return a value. Growing a rule adds a field or a function. Existing return
   shapes stay: add keys to a map, never rename or remove them. This is the convention for future
   changes.
7. **Tests sit at the page and the context.** LiveView tests and context tests (public context
   functions against Postgres) pin behaviour. A rule keeps its own unit tests only where it has edge
   cases worth pinning directly (tier boundaries, thresholds, normalisation), and those tests build
   a test-owned `%Channel{}` with just the field the rule reads and assert results through the
   rule's public function.

## The structs

`GoodDeal.Channel`: one channel's calibration. `Calibration.channel(:storefront | :portal)` builds it.

| Field | Default | Storefront | Portal | Read by |
|---|---|---|---|---|
| `name` | enforced | `:storefront` | `:portal` | `Calibration.pricing/2` (chooses the discount rule) |
| `shipping_methods` | `[]` | three methods | the same three | `ShippingMethod.find/2`, the pages' shipping picker |
| `default_shipping_method` | `nil` | `"standard"` | `"standard"` | `ShoppingCart.get_or_create_open_cart/1` |
| `promo_codes` | `%{}` | SAVE10, SAVE20, HALF | none | `PromoCode.valid?/2`, `discount/2` |
| `gift_wrap_price` | `0` | 299 | 0 | `Calibration.pricing/2` |
| `volume_tiers` | `[]` | none | 5% from 50,000, 10% from 200,000 | `VolumeTier.discount/2` |
| `low_stock_threshold` | `nil` | 5 | 5 | `StockStatus.of/2` |
| `postal_code_length` | `nil` | 3..10 | 3..10 | `ShoppingCart.change_address/2`, `save_address/2` |
| `po_number` | `nil` | PO format and message | the same | `Orders.change_purchase_order/2`, `submit_portal_order/3` |

The values both channels share are written once (`shared/1`), so a later split is a change to one
channel's value.

`GoodDeal.Shop`: what a page holds for its session.

| Field | Meaning |
|---|---|
| `channel` (enforced) | the channel's `%Channel{}` |
| `cart_id` | the session's cart (storefront) or draft (portal); `nil` before `EnsureCart` creates one |

`CartSession.on_mount/4` assigns `shop` (storefront) and `portal_shop` to every LiveView;
`CartSession.shop/2` builds one and `EnsureCart` uses it per session key (the router names the
channel next to the key). Both structs sit in platform: they are data types every layer may hold.

Functions that take them:

| Module | Takes `%Shop{}` first | Takes `%Channel{}` first |
|---|---|---|
| `ShoppingCart` | `get_or_create_open_cart/1`, `apply_promo_code/2`, `select_shipping_method/2`, `change_address/2`, `save_address/2`, `list_cart_items/1`, `list_saved_items/1`, `get_cart_item!/2`, `get_cart_item_for_product/2`, `add_item/2,3`, `check_stock/1`, `list_wishlist/1`, `in_wishlist?/2`, `toggle_wishlist/2`, `remove_from_wishlist/2`, `move_wishlist_item_to_cart/2` | |
| `Orders` | `change_purchase_order/1,2`, `complete_checkout/2`, `submit_portal_order/3` | |
| domain | | `PromoCode.valid?/2`, `discount/2`; `ShippingMethod.find/2`; `VolumeTier.discount/2`; `StockStatus.of/2` |
| app | | `Calibration.pricing/2`, `ShopComponents.stock_badge` (`channel` attr) |

Functions on one entity keep the entity: `create_cart/1`, `get_cart!/1`, `update_cart/2`, and the
`%CartItem{}` functions (`update_item/2`, `change_quantity/2`, `toggle_gift_wrap/1`,
`save_for_later/1`, `move_to_cart/1`, `delete_item/1`, `restore_item/1`). `ShippingMethod.cost/2`
is configured by its `%ShippingMethod{}` and `Pricing.summary/2` by its `%Pricing{}`, as in V54.

## Layer map

| Layer | Peers may call each other | Modules |
|---|---|---|
| app | yes | LiveViews, `ShopComponents`, `UndoRemoval`, `CartSession`, `Plugs.EnsureCart`, `Router`, `PageController`, `PageHTML`, `Layouts`, `Calibration`, `GoodDealWeb` (its `use` macros import `ShopComponents`) |
| contexts | no | `Catalog`, `ShoppingCart`, `Orders`, `Payments` |
| domain | no | `GoodDeal.Domain.{Pricing, ShippingMethod, VolumeTier, PromoCode, StockStatus}` |
| platform | yes | `Repo`, `Mailer`, `ProductEvents`, `Channel`, `Shop`, the Ecto schemas, `Payments.Provider` and `InProcessProvider`, `GoodDeal` |

V54's DESIGN.md has what moved from V0 to V54. Everything there still holds except the rows this
table replaces.

## What changed from V54

| V54 | V55 | Rule |
|---|---|---|
| `Calibration.shipping_methods/0`, `new_cart/0`, `promo_codes/0`, `gift_wrap_price/0`, `low_stock_threshold/0`, `postal_code_length/0`, `po_number/0` | fields of `%Channel{}` from `Calibration.channel/1` | 5 |
| `Calibration.storefront_pricing/1`, `portal_pricing/1` | `Calibration.pricing(channel, cart)` | 5: named for the concept, not the channel |
| context functions taking a cart id, or a `%Cart{}` plus separate calibration values | take a `%Shop{}`; those that update the cart load it by `shop.cart_id` and return it as before | 5 |
| `complete_checkout(cart, items, summary)`, `submit_portal_order(cart, items, summary, po_params, po_number)` | `complete_checkout(shop, summary)`, `submit_portal_order(shop, summary, po_params)` | 5 |
| `Pricing.summary/2` map | the same keys plus `items`, the lines it priced, so `Orders` places an order from the summary alone | 6: a key added |
| `PromoCode.valid?(codes, code)`, `discount(codes, code)`, `ShippingMethod.find(methods, id)`, `VolumeTier.discount(tiers, subtotal)`, `StockStatus.of(stock, threshold)` | first argument is the `%Channel{}` (for `StockStatus`, the order is now channel then stock) | 5, 6 |
| `stock_badge` and the portal's add button read `Calibration.low_stock_threshold/0` | the page passes its shop's channel | 5 |
| `cart_id` and `portal_cart_id` assigns | `shop` and `portal_shop` | 5 |
| `EnsureCart, key: ...` | `EnsureCart, key: ..., channel: ...` | 5 |

The largest context function arity went from 5 (`submit_portal_order/5`) to 3
(`submit_portal_order/3`, and `add_item/3`, whose third argument is V0's `\\ 1` quantity).

## Tests moved up or removed

V54 had 155 tests; V55 has 146. No LiveView or context assertion changed. Calls whose signatures
changed were adapted, through a `shop/2` fixture helper (`shop(cart_id, channel \\ :storefront)`).
The one context test that went through a different function is "a new cart is open": it used
`create_cart(Calibration.new_cart())` and now uses `get_or_create_open_cart(shop(nil))`, with the
same assertion.

`test/good_deal_web/calibration_test.exs` (9 tests) is gone. It pinned calibrated values through
`Calibration` accessors and the pricing builders, so every accessor rename broke it.

| V54 test | Now | Why |
|---|---|---|
| subtotal is the sum…; total adds standard shipping | removed | cart page "shows item count, subtotal, shipping and total" |
| an empty cart ships free | removed | cart page "an empty cart says so and disables checkout" (Free); rule test "an empty cart ships free" |
| standard shipping is free from 5000, other methods are not | moved up: cart page "standard shipping is free at exactly 5,000 and charged at 4,999" | other methods are pinned by "choosing a shipping method…" ($12.99) and portal "shipping methods are the storefront's" ($24.99) |
| promo codes discount the subtotal by their percentage | moved up: cart page "each promo code takes its own percentage off the subtotal" | V54's page tests applied only SAVE10 |
| gift wrap charges 299 per wrapped item on the storefront, not on the portal | removed | cart page "gift wrap adds 299…"; the portal has no gift-wrap control, and `gift_wrap_price() == 299` pinned a calibration shape |
| total = subtotal − discount + gift wrap + shipping | moved up: cart page "the total is subtotal less discount plus gift wrap plus shipping" | no page test combined all four |
| volume tiers apply 5% from 50,000 and 10% from 200,000 | moved up: portal "the 5% tier starts at exactly 50,000" | 10% at 200,000 is pinned by "volume pricing applies by tier and reprices across boundaries" (20 × 10,000) |
| lists the store's shipping methods and promo codes | removed | a calibration-shape test; unknown methods are pinned by `select_shipping_method/2`, normalisation by `apply_promo_code/2`, case by the `PromoCode` rule test |
| stock is out at 0, low at 5 or fewer, in stock above | moved up: product list "stock shows as low at 5 and in stock at 6" | out of stock at 0 is pinned by the cart and portal page tests |

Other rule tests:

- `test/good_deal/domain/pricing_test.exs` (4 tests) removed. It built `%Pricing{}` with `struct!`
  and closures, so it was pinned to the config shape, and the page tests already pin line totals,
  discount, gift wrap, and shipping by subtotal on both channels.
- `ShippingMethod` "finds a method by id" removed: a list lookup, pinned by
  `select_shipping_method/2`.
- Kept, 8 tests: `PromoCode` (normalisation of whitespace, case and nil; matching; unknown and nil
  codes), `ShippingMethod.cost/2` (the free-above boundary, the empty cart), `StockStatus` (the
  boundaries), `VolumeTier` (the boundaries, no tiers). Each builds `%Channel{name: :test, ...}` with
  only the field it reads, so a new channel field does not touch them.

The three calibrated boundaries (the 5% tier at 50,000, free standard shipping at 5,000, low stock
at 5) are pinned at their real values by the three page tests above, each on both sides of the
boundary. Moving any of the three by one in either direction in `Calibration` fails its test; that
was checked by hand and reverted. The rules' own boundary tests use test-owned values.

## Cost

- Production lines (`lib/**/*.ex`) 2,924 to 2,974 (+50). New: `Channel` 19, `Shop` 9. `Calibration`
  64 to 60, `ShoppingCart` 206 to 213 (it loads the cart by id in four functions),
  `Orders` 107 to 111, `CartSession` 18 to 23, the domain rules 86 to 97 (an alias and a struct
  pattern each). The pages are about the same (`CartLive.Index` 240 to 236, `PortalLive.Index` 192
  to 194).
- Test lines 2,091 to 1,996: 14 tests deleted, 5 page tests added (two rewrite calibration tests, three pin the calibrated boundaries), call sites shortened.
- Six context functions now read the cart by id where V54 used the page's `%Cart{}`:
  `apply_promo_code/2`, `select_shipping_method/2`, `change_address/2`, `save_address/2`,
  `complete_checkout/2`, `submit_portal_order/3`. `change_address/2` runs on every keystroke of the
  checkout address form, so that is one more query per keystroke.
- The summary assign now holds the priced items as well.
- Two conventions sit side by side in `ShoppingCart`: session-scoped functions take the shop,
  entity functions take the entity. A test or page that has only an entity id (`get_cart!/1`)
  still passes the id.

## Lint checks

`lint.exs` is V54's, with `GoodDeal.Channel` and `GoodDeal.Shop` added to the platform layer. It
scores R1, R3, R5, R6 and R7 (with `clone`) along with the rest of the default required and advisory
checks that are not about ports. Turned off, as in V54, because form 1b adopts no ports, wiring,
features or composition-only pages:

| Check | Why off |
|---|---|
| `r9` | owned port interfaces; the one `@callback` here is V0's payment provider |
| `r10`, `r10_aggregate` | shared entities between features; there is no features layer |
| `r11`, `r11_share` | composition-only pages; rule 4 lets pages hold logic |
| `ports`, `ports_unwired`, `ports_computed` | declared ports |
| `wiring_closure`, `hops`, `vocabulary` | wiring and message hops between parts |
| `subcomponent` | LiveComponents inside a composition layer (`ProductLive.FormComponent` is V0's generated form) |

There are no `ala:accept` lines. Result, the same at every tier:
`by_rule=%{app_share: 1, clone: 1, module_avg: 1, public_surface: 1}`, score 100.
This is V54's result unchanged; the function count is 205. `app_share`, `module_avg` and
`public_surface` are reported only. The `clone` is scored under
`--strict` and rounds to 100. It flags the two one-line `remove`/`undo` handlers in `CartLive` and
`PortalLive`, each calling `UndoRemoval` with its own stream and then its own `assign_summary/1`.
That is two pages placing one shared part, which is what the check asks for, so I left it.
`public_surface` notes `ShoppingCart` has 26 public functions, as in V0.
