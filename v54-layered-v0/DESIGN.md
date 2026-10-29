# V54 design: layered V0 (ALA form 1)

Form 1 keeps the parts of ALA that need no ports. Earlier change-cost runs
(`ala_lab/docs/change-cost-sequence-2026-10-21.md`, `change-cost-light-2026-10-22.md`) credited the
ALA variants with fewer broken tests per change, a cross-cutting rule checked at one point (S06), and
cheap calibration changes (S05). They also cost 1.3 to 1.6 times V0, nearly all of it in ports and
wiring. V54 tests whether the cheap parts carry the benefits on their own. It is a reading of the
checklist, not Spray's ALA: his core also composes by ports.

## The four rules

1. **Dependencies point down (R1).** Four layers, below. Contexts may not call each other, and
   neither may domain rules.
2. **Calibration at the top (R3).** Every application literal lives in `GoodDealWeb.Calibration`
   and reaches lower layers as an argument or a configuration struct. No context or domain module
   holds a §7 value or a channel name.
3. **Rules as named pure modules (R6, R7).** A rule is a module named for its concept, configured
   by its caller, with no I/O and a test of its own. One-line calls stay where they are.
4. **Everything else is V0.** Contexts, LiveViews, streams, PubSub, `start_async`, Mox. Pages
   branch, loop and pass values between calls as V0's do.

## Layer map

| Layer | Peers may call each other | Modules |
|---|---|---|
| app | yes | LiveViews, `ShopComponents`, `UndoRemoval`, `CartSession`, `Plugs.EnsureCart`, `Router`, `PageController`, `PageHTML`, `Layouts`, `Calibration`, `GoodDealWeb` (its `use` macros import `ShopComponents`) |
| contexts | no | `Catalog`, `ShoppingCart`, `Orders`, `Payments` |
| domain | no | `GoodDeal.Domain.{Pricing, ShippingMethod, VolumeTier, PromoCode, StockStatus}` |
| platform | yes | `Repo`, `Mailer`, `ProductEvents`, the Ecto schemas, `Payments.Provider` and `InProcessProvider`, `GoodDeal` |

`lint.exs` holds the same map. App peers are allowed because LiveViews read `Calibration` and use
`UndoRemoval` and the page components, which is V0's shape. The schemas stay at V0's module names
(`GoodDeal.Catalog.Product` and so on) and sit in platform: a context and the next one share a
schema as a data type, never by calling each other.

`Pricing` takes its discount and shipping as functions rather than calling `VolumeTier`,
`PromoCode` or `ShippingMethod`. `Calibration` builds one `%Pricing{}` per channel
(`storefront_pricing/1`, `portal_pricing/1`), so the channel difference that V0 spelled as
`volume_pricing: true` and `gift_wrap: true` is now which rules the app hands in.

## What moved

| V0 location | V54 location | Why |
|---|---|---|
| `ShoppingCart.Pricing` attributes: shipping methods, promo codes, gift wrap 299, volume tiers | `GoodDealWeb.Calibration` | R3 |
| `ShoppingCart.Pricing.summary/2` with `volume_pricing:`/`gift_wrap:` options | `Domain.Pricing.summary/2`, configured by `Calibration.storefront_pricing/1` or `portal_pricing/1` | R3, R6 |
| volume tier lookup (private in `Pricing`) | `Domain.VolumeTier` | R6 |
| shipping cost and free-above rule (private in `Pricing`) | `Domain.ShippingMethod` (struct + `cost/2`, `find/2`) | R6 |
| promo normalization in `ShoppingCart`, lookup in `Pricing` | `Domain.PromoCode` | R6 |
| `Catalog.stock_status/1` and `@low_stock_threshold 5` | `Domain.StockStatus.of/2`; threshold in `Calibration` | R3, R6 |
| `Catalog.subscribe/0`, `Catalog.broadcast/2`, topic | `GoodDeal.ProductEvents` (platform), topic `"product_events"` | `Orders` called `Catalog.broadcast`; the shared need goes down |
| `Orders` calling `ShoppingCart.Pricing.summary` | page computes the summary; `complete_checkout/3`, `submit_portal_order/5` take it | no context calls another; the page already prices the cart |
| `Orders.reference/1` (`"GD-"`, width 6) | `ShopComponents.order_reference/1` | page words and a width are app literals |
| PO format and "must look like PO-1234" in `PurchaseOrder` | `Calibration.po_number/0`, passed through `Orders` | §7 message text |
| postal-code length 3..10 in `Address` | `Calibration.postal_code_length/0`, passed through `ShoppingCart` | app literal |
| `Cart` schema default `shipping_method: "standard"` | `Calibration.new_cart/0`, passed by `EnsureCart` to `get_or_create_open_cart/2` | app literal |
| session keys repeated in `CartSession` and `Router` | defined once in `CartSession` | R5 |
| undo stream insert/delete and "Item restored" flash, written in both pages | `UndoRemoval.remove/3`, `undo/2` take the stream name | the clone check (R7) |

The undo window was already in `config/config.exs` (5 s, 1 s in test) and read only by the
app-layer `UndoRemoval`, so it stays there. The migration still has the column default `"standard"`;
migrations are history and the linter does not read them.

## Cost

- Production lines 2,868 to 2,924 (+56). The new modules add 171 lines (`Calibration` 64, five domain
  rules 86, `ProductEvents` 21) and `ShoppingCart.Pricing` (79) is gone. The pages got shorter
  (`CartLive.Index` 257 to 240, `PortalLive.Index` 205 to 192).
- Context signatures grew a calibration argument: `apply_promo_code/3`, `select_shipping_method/3`,
  `change_address/3`, `save_address/3`, `get_or_create_open_cart/2`, `change_purchase_order/2`,
  `complete_checkout/3`, `submit_portal_order/5`. Tests that called them pass `Calibration` values,
  and their assertions are unchanged. `submit_portal_order/5` is the worst of it: five arguments, two
  of them configuration.
- `create_cart/1` now needs its attrs, since the schema no longer supplies a default shipping method.
  The fixture merges `Calibration.new_cart/0`.
- Tests: 142 to 155. `pricing_test.exs` became `test/good_deal_web/calibration_test.exs` with the same
  assertions through the calibrated rules; the `stock_status/1` test moved there too. Each domain rule
  has its own unit test with test-owned configuration (22 new tests).

## Lint checks

`lint.exs` scores R1, R3, R5, R6 and R7 (with `clone`) along with the rest of the default required
and advisory checks that are not about ports. Turned off, because form 1 adopts no ports, wiring,
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
`app_share`, `module_avg` and `public_surface` are reported only. The `clone` is scored under
`--strict` and rounds to 100. It flags the two one-line `remove`/`undo` handlers in `CartLive` and
`PortalLive`, each calling `UndoRemoval` with its own stream and then its own `assign_summary/1`.
That is two pages placing one shared part, which is what the check asks for, so I left it.
`public_surface` notes `ShoppingCart` has 26 public functions, as in V0.
