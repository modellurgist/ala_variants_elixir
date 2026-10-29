# V56 design: layered V0 with stable, honest interfaces (ALA form 1c)

Form 1b (V55) ran the six-step change sequence at V0's cost and broke 0.41 times as many existing
tests as V0. The reviewer found that part of the gain came from contracts no test checks: a session
id that defaulted to nil, a promo minimum checked only in the shared page module, and fewer tests
(`ala_lab/docs/change-cost-form1-2026-10-24.md`, the form 1b section). Those were S04 and S06
changes, so V55's baseline doesn't contain them. It does contain the same two habits: struct
fields that a correct program must set but that default anyway, and guards that only a page
enforces. V56 is V55 changed as little as possible to remove them. Behaviour through the pages is
V55's. The one difference is on paths no page reaches, listed under "What changed from V55".

## The nine rules

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
   narrower struct it is configured by) as its first argument. A new input later is a new field,
   not a new parameter (rule 8 says when the field may have a default), and a value that may one day differ by channel is already
   a field of the channel, so splitting it changes a value, not a name.
6. **Rules are extended, not reshaped.** A rule's public functions take the configuration struct
   and a value and return a value. Growing a rule adds a field or a function. Existing return
   shapes stay: add keys to a map, never rename or remove them. This is the convention for future
   changes.
7. **Tests sit at the page and the context.** LiveView tests and context tests (public context
   functions against Postgres) pin behaviour. A rule keeps its own unit tests only where it has edge
   cases worth pinning directly (tier boundaries, thresholds, normalisation), and those tests build
   a test-owned `%Channel{}` and assert results through the rule's public function. Since V56
   they build it with `channel_fixture/1`, which gives every enforced field a neutral value, and
   override only the field the rule reads (rule 8).

Two corrections, added in V56:

8. **A value the domain needs is an enforced key, not a default.** In every configuration or
   context struct (`%Channel{}`, `%Shop{}`, `%Pricing{}`, any added later), a field that a correct
   program must always set is in `@enforce_keys` and has no default. A default is allowed only for
   a value that is truly optional, where its absence has a defined, correct meaning. A new required
   input therefore breaks the places that build the struct. That break is deliberate: it is the one
   honest break rule 5 should leave. Schemas follow the same reading: a column the domain requires
   is required in the changeset.
9. **A rule that guards data is enforced where the data is written.** Validity, minimums, stock,
   ownership and similar guards are checked by the context function that writes the data, which
   refuses with a tagged error (`{:error, atom}` or `{:error, changeset}`). A page may check earlier
   to show a message, but the context never relies on the page. A rule's meaning never changes under
   an unchanged name: if a key or function would mean something different, give the new meaning a
   new name.

Both are conventions for future changes as well. A new channel value that every channel must
state is a new enforced key; a new guard (a promo minimum, say) goes in the context function that
writes the guarded field, with a context test, even when a page also checks it.

## The structs

`GoodDeal.Channel`: one channel's calibration. `Calibration.channel(:storefront | :portal)` builds
it with `struct!/2`, so a missing enforced key fails at the first call.

| Field | Enforced or default | Storefront | Portal | Why |
|---|---|---|---|---|
| `name` | enforced | `:storefront` | `:portal` | `Calibration.pricing/2` chooses the discount rule by it |
| `shipping_methods` | enforced (V55: `[]`) | three methods | the same three | with none, `Calibration.pricing/2` crashes on the cart's method; there is no correct empty value |
| `default_shipping_method` | enforced (V55: `nil`) | `"standard"` | `"standard"` | every new cart needs one; the cart schema requires it |
| `gift_wrap_price` | enforced (V55: `0`) | 299 | 0, stated | a default of 0 would let a channel that forgets it wrap for free; the portal now says 0 itself |
| `low_stock_threshold` | enforced (V55: `nil`) | 5 | 5 | `StockStatus.of/2` compares against it; `nil` would mis-sort every stock level |
| `postal_code_length` | enforced (V55: `nil`) | 3..10 | 3..10 | `Address.changeset/3` validates with it |
| `po_number` | enforced (V55: `nil`) | PO format and message | the same | `PurchaseOrder.changeset/3` matches on it |
| `promo_codes` | default `%{}` | SAVE10, SAVE20, HALF | none | absence means the channel takes no codes: every code is refused, nothing is discounted |
| `volume_tiers` | default `[]` | none | 5% from 50,000, 10% from 200,000 | absence means no volume discount: full price |

The two defaults are offers a channel may lack, and in both cases absence fails safe (a refusal or
full price). `gift_wrap_price` looks like the same kind of field, but its absence would undercharge,
so it is enforced. The values both channels share are still written once (`shared/2`), which now
takes each channel's own fields as a keyword list.

`GoodDeal.Shop`: what a page holds for its session.

| Field | Enforced or default | Why |
|---|---|---|
| `channel` | enforced | every session-scoped function reads it |
| `cart_id` | enforced (V55: defaulted to `nil`), may be `nil` | every builder must say which cart it means. `nil` is a stated value meaning "no cart yet", and only `get_or_create_open_cart/1` accepts it; `add_item/3` with a nil cart refuses (cart item schema), and the read functions raise |

`GoodDeal.Domain.Pricing`: `discount`, `shipping`, `shipping_label` and, since V56,
`gift_wrap_price` are enforced (V55 defaulted `gift_wrap_price` to 0, for the reason given under
`%Channel{}`). `GoodDeal.Domain.ShippingMethod` keeps `free_above: nil` as its one default: absence
means the method is never free, which is correct for express and overnight.

Schemas, with the fields their changesets require:

| Schema | Required | Optional, and why |
|---|---|---|
| `Product` | `name`, `amount` | `stock` defaults to 0 (a new product has nothing to sell yet; V0's generated test pins "only name and amount are required"); `description`, `thumbnail` |
| `Cart` | `status`, `shipping_method` | `promo_code` (no code), `address` (set at checkout) |
| `CartItem` | `quantity` and, since V56, `cart_id` and `product_id` | none |
| `Address` | `name`, `line1`, `city`, `postal_code` | none |
| `Order` | `source`, `subtotal`, `total`, line items, and since V56 `discount`, `gift_wrap`, `shipping`, plus `address` for a storefront order and `po_number` for a portal order | `cart_id` (nilified if the cart is deleted) |
| `LineItem` | `name`, `unit_price`, `quantity` | `product_id` (nilified if the product is deleted) |
| `PurchaseOrder` | `number`, in the channel's format | none |

`Order`'s `discount`, `gift_wrap` and `shipping` lost their schema default of 0: an order records
what it charged, so a missing amount is an error, not a zero. The database defaults stay; the
migrations are unchanged.

## Guard audit

Each guard, where V55 enforced it, and where V56 does.

| Guard | V55 | V56 |
|---|---|---|
| Promo code is one of the channel's | `apply_promo_code/2` checked it, but `create_cart/1` and `update_cart/2` also wrote `promo_code` unchecked | only `apply_promo_code/2` writes it; `Cart.status_changeset/2` no longer casts it. Context test: "apply_promo_code/2 rejects an unknown code" |
| Shipping method is one of the channel's | `select_shipping_method/2`, with the same two unchecked writers | only `select_shipping_method/2` writes it (and `get_or_create_open_cart/1` writes the channel's default). Context test: "select_shipping_method/2 accepts only known methods" |
| Stock covers the order | `check_stock/1` (context, before payment) and the guarded decrement in `complete_checkout/2` | unchanged; confirmed. Context tests: "check_stock/1 reports…", "rolls back when stock ran out meanwhile" |
| Quantity at least 1 | `CartItem` changeset; the portal page clamps first | unchanged; confirmed. Context test: "add_item/3 rejects a quantity below 1" |
| Cart non-empty at checkout or submit | `check_stock/1`; the portal page's review step; `Order` requires line items | unchanged; confirmed. Context tests: "an order needs line items" (portal) and the new storefront test |
| PO number format | `submit_portal_order/3` validates before writing | unchanged; confirmed, and `Order` now requires `po_number` on a portal order. Context test: "requires a PO number like PO-1234" |
| Address fields and postal code length | `save_address/2` | unchanged; confirmed. Context test: "save_address/2 validates and stores the address" |
| A storefront order has an address | page only: the payment step is reachable only with a saved address | `Order` requires `address` on a storefront order, so `complete_checkout/2` refuses. New context test |
| An order's items belong to the shop's cart | page only: the page priced its own cart's items | `Orders` refuses with `{:error, :not_in_cart}` inside the order transaction, on both paths. New context tests (storefront and portal) |
| A cart item belongs to a cart | the database's not-null constraint (raises) | `CartItem` changeset requires `cart_id` and `product_id`, so `add_item/3` refuses. New context test |
| Item reads and edits stay in the session's cart | `get_cart_item!/2` and the list functions filter by `shop.cart_id`; the entity functions (`update_item/2`, `delete_item/1`, …) take an item the page loaded that way | unchanged. The entity functions still trust that their item came from a scoped read; checking it again would mean passing the shop to every entity function, a larger change than this audit called for |

Pricing itself (the totals an order records) still comes from the page's summary, as in V55: the
context cannot rebuild a `%Pricing{}` without the app layer's calibration (rule 2). The ownership
check above covers which items are charged; it does not re-price them.

## Layer map

| Layer | Peers may call each other | Modules |
|---|---|---|
| app | yes | LiveViews, `ShopComponents`, `UndoRemoval`, `CartSession`, `Plugs.EnsureCart`, `Router`, `PageController`, `PageHTML`, `Layouts`, `Calibration`, `GoodDealWeb` (its `use` macros import `ShopComponents`) |
| contexts | no | `Catalog`, `ShoppingCart`, `Orders`, `Payments` |
| domain | no | `GoodDeal.Domain.{Pricing, ShippingMethod, VolumeTier, PromoCode, StockStatus}` |
| platform | yes | `Repo`, `Mailer`, `ProductEvents`, `Channel`, `Shop`, the Ecto schemas, `Payments.Provider` and `InProcessProvider`, `GoodDeal` |

V54's and V55's DESIGN.md have what moved from V0 to V54 and from V54 to V55. Everything there
still holds except the rows below.

## What changed from V55

| V55 | V56 | Rule |
|---|---|---|
| `%Channel{}` enforced only `name` | enforces `name`, `shipping_methods`, `default_shipping_method`, `gift_wrap_price`, `low_stock_threshold`, `postal_code_length`, `po_number`; `Calibration` builds it with `struct!/2` and states the portal's gift-wrap price of 0 | 8 |
| `%Shop{}` defaulted `cart_id` to `nil` | `cart_id` enforced (may still be given as `nil`) | 8 |
| `%Pricing{}` defaulted `gift_wrap_price` to 0 | enforced | 8 |
| `ShoppingCart.create_cart/1`, `update_cart/2` (cast status, promo code and shipping method) | gone; `set_cart_status/2` sets the status, and `get_or_create_open_cart/1` is the only way to make a cart. A new name, because the function no longer accepts the other two fields | 9 |
| `Cart.changeset/2` | `Cart.status_changeset/2`, casting only `status` | 9 |
| `Order` defaulted `discount`, `gift_wrap`, `shipping` to 0; required neither address nor PO number | all three required; `address` required for `:storefront`, `po_number` for `:portal` | 8 |
| `CartItem` required only `quantity` | also `cart_id`, `product_id` | 8 |
| `Orders` placed any items the summary held | refuses items from another cart with `{:error, :not_in_cart}` | 9 |

Behaviour through the pages is unchanged; all 146 of V55's tests pass with their assertions as
they were. Off the pages' paths, three things differ. A storefront order without an address is now
refused, where V55 would have created one with a nil address (no page can reach the payment step
without a saved address). A summary holding another cart's items is refused, where V55 would have
ordered them; the checkout page shows its generic failure flash for that, and the portal page has
no clause for it and would crash, since only a crafted call can produce it. `add_item/3` on a nil
cart returns an error changeset, where V55 raised a not-null error from the database.

## Tests

V55 had 146 tests; V56 has 149. No assertion changed. What changed:

- `test/support/fixtures/channel_fixtures.ex` (new): `channel_fixture/1` builds a test-owned
  `%Channel{}` with a neutral value for every enforced field. The `PromoCode`, `StockStatus` and
  `VolumeTier` tests used `%Channel{name: :test, field: ...}` literals, which no longer compile;
  they now call `channel_fixture(field: ...)` from a private `channel/0` (not a module attribute,
  because the fixture holds a regex). This is the break rule 8 intends, kept to one fixture.
- `cart_fixture/1` built carts with `create_cart/1`. It now starts from `get_or_create_open_cart/1`
  and applies `:promo_code` and `:status` through `apply_promo_code/2` and `set_cart_status/2`, so
  a fixture cart passes the same guards as a real one. Its callers are unchanged.
- "status is one of open, completed, abandoned" calls `set_cart_status(cart, status)` instead of
  `update_cart(cart, %{status: status})`.
- "rolls back when stock ran out meanwhile" saves an address before checking out. Without it the test
  failed: the new address requirement refused the order before the stock ran out.
- Added: `complete_checkout/2` "refuses a cart with no address, an empty summary, or another cart's
  items"; `submit_portal_order/3` "refuses another cart's items"; `add_item/3` "refuses a shop with
  no cart".

The two ownership and address tests were checked by hand: removing the ownership check fails both
ownership tests, and removing the storefront address requirement fails the storefront test. Both
edits were reverted.

## Cost

- Production lines (`lib/**/*.ex`) 2,974 to 2,994 (+20). `Calibration` 60 to 64, `Orders` 111 to
  116, `Order` 37 to 45, `Cart` 24 to 27, `Shop` 9 to 10, `Channel` 19 to 18; `ShoppingCart` stays
  at 213 (two public writers out, `set_cart_status/2` and a private `write_cart/2` in).
- Test lines 1,996 to 2,068 (+72): the channel fixture (23), three new tests, the cart fixture.

## Lint checks

`lint.exs` is V55's unchanged (V54's, with `GoodDeal.Channel` and `GoodDeal.Shop` added to the platform layer). It
scores R1, R3, R5, R6 and R7 (with `clone`) along with the rest of the default required and advisory
checks that are not about ports. Turned off, as in V54 and V55, because form 1c adopts no ports, wiring,
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
This is V55's result; the function count is 207 (V55: 205). `app_share`, `module_avg` and
`public_surface` are reported only. The `clone` is scored under
`--strict` and rounds to 100. It flags the two one-line `remove`/`undo` handlers in `CartLive` and
`PortalLive`, each calling `UndoRemoval` with its own stream and then its own `assign_summary/1`.
That is two pages placing one shared part, which is what the check asks for, so I left it.
`public_surface` notes `ShoppingCart` has 25 public functions (V55: 26; `create_cart/1` and
`update_cart/2` gave way to `set_cart_status/2`).
