# V59 design: light ALA (form 1c with composition roots)

Hybrid 1 (V58) ran the ten-change sequence at 1.12 times V0's tokens, near form 1c's 1.07, and
its roots cost 49 production lines over the run (`ala_lab/docs/change-cost-form1-2026-10-24.md`,
"Hybrid 1"). The run also found two faults in the form, not in the changes. At S07 a reorder
written as a LiveView event used the shop its page built at mount. After the portal's live
navigation that shop named a completed draft, and the reordered lines went into it and were
lost. At S04 the shop builder took the cart id as a positional argument, so adding the session id
changed its arity and broke 119 tests through the shared fixture. V59 is V58 with one rule added
(12) and one extended (11) to close those two. It is the variant the write-up recommends as light
ALA. This is a checklist reading, not Spray's ALA, which also composes by ports.

## The twelve rules

The first four are form 1's. The `R` numbers are the checklist's
(`ala_checklist/ala_checklist_elixir.md`).

1. **Dependencies point down (R1).** Four layers, below. Contexts may not call each other, and
   neither may domain rules. `Orders` places an order from the summary the page hands it; it
   never calls `ShoppingCart` to price one.
2. **Calibration at the top (R3).** Every application literal lives in `GoodDealWeb.Calibration`
   and reaches lower layers inside a configuration struct. `StockStatus.of(channel, stock)` reads
   `channel.low_stock_threshold`; no context or domain module holds a §7 value or a channel name.
3. **Rules as named pure modules (R6, R7).** A rule is a module named for its concept, configured
   by its caller, with no I/O: `ShippingMethod.cost(method, subtotal)`, `VolumeTier.discount/2`,
   `PromoCode.valid?/2`. One-line calls stay where they are.
4. **Everything else is V0.** Contexts, LiveViews, streams, PubSub, `start_async`, Mox. Pages
   branch, loop and pass values between calls as V0's do; `CheckoutLive.Index` calls
   `check_stock`, then the provider, then `Orders.complete_checkout` in its own handlers.

Three about interfaces, from form 1b:

5. **Configuration is passed once, as a struct.** A channel's calibration is one `%Channel{}`. A
   page's session values travel in one `%Shop{}`, which carries the channel. A context function
   that needs either takes the shop first (`ShoppingCart.apply_promo_code(shop, code)`); a rule
   takes the channel or the narrower struct it is configured by. A new input is a new field, not a
   new parameter.
6. **Rules are extended, not reshaped.** A rule's public functions take the configuration struct
   and a value and return a value. Growing a rule adds a field or a function. Existing return
   shapes stay: `Pricing.summary/2` may gain keys but keeps `subtotal`, `discount`, `total`.
7. **Tests sit at the page and the context.** LiveView tests and context tests against Postgres
   pin behaviour. A rule keeps its own unit tests only where it has edge cases worth pinning
   (`VolumeTierTest`: the 5% tier starts at exactly 50,000), built with `Calibration.channel/2`
   and one override.

Two corrections, from form 1c:

8. **A value the domain needs is an enforced key, not a default.** `%Channel{}` enforces seven
   keys and defaults only `promo_codes: %{}` and `volume_tiers: []`, where absence means "no offer".
   `%Shop{}` enforces `channel` and `cart_id`; `cart_id: nil` means "no cart yet" and only
   `get_or_create_open_cart/1` accepts it.
9. **A rule that guards data is enforced where the data is written.** The context function that
   writes refuses with a tagged error. `apply_promo_code/2` returns `{:error, :invalid_promo_code}`
   whatever the page checked first. A rule's meaning never changes under an unchanged name.

Two from hybrid 1, the second extended here:

10. **A composition root per page.** Each LiveView that uses configured parts has one private
    `parts/…`, called from `mount`, that builds the session's `%Shop{}`, the pricing for its
    channel and shared app-layer helpers with their settings. Where two pages need the same
    parts, the root composes one builder and names its own values. The cart page and the portal
    both edit a session cart line by line, so each root is one call:

    ```elixir
    defp parts(session),
      do: CartSession.editor_parts(session, :storefront, :items, &assign_summary/1)
    ```

    `editor_parts/4` returns the channel's shop, its pricing, and `%UndoRemoval{}` over the
    page's stream, repriced with the page's own `assign_summary/1`. `mount` assigns the result
    once as `parts`. Handlers and templates read `parts.shop`, `parts.pricing.(cart)` and
    `parts.undo` and never call `Calibration`, `CartSession` or `Application.fetch_env!`.
    Nothing is wired: handlers call the parts and use what they return. The reprice function is
    a strategy the root passes down, not a port: `UndoRemoval` calls it after a removal or an
    undo and uses what it returns.
11. **Builders take keyword overrides, and tests build through them.** A builder of a config or
    context struct takes the values it cannot do without as arguments and everything else as a
    keyword list, which it hands to `struct!/2`. `struct!/2` refuses a missing enforced key and an
    unknown one, so a new field is one more option and never a new arity:

    ```elixir
    def shop(channel, overrides),
      do: struct!(Shop, [channel: Calibration.channel(channel)] ++ overrides)
    ```

    The three builders are `Calibration.channel(name, overrides \\ [])`,
    `CartSession.shop(channel, overrides)` (with `cart_id:` required by the struct) and
    `Calibration.pricing(channel, cart, overrides \\ [])`. Tests never write a config or context
    struct literal. They call `shop(:storefront, cart_id: cart.id)`, which the fixtures delegate
    to `CartSession.shop/2` unchanged, and `Calibration.channel(:portal, volume_tiers: [])`.
12. **A write to a session cart sees a current cart.** An action that changes a cart found
    through the session either runs through an HTTP request, where `Plugs.EnsureCart` resolves
    an open cart, or checks the cart is still open first. A LiveView event never writes to a cart
    id captured at mount without that check. Each root's `mount` attaches it:

    ```elixir
    |> CartSession.guard_open_cart(shop, ~p"/cart")
    ```

    Before every event (or only the ones named in `only:`) the hook asks
    `ShoppingCart.cart_closed?/1`. If the cart has closed, it drops the event, flashes "That cart
    is closed, so nothing changed. Please try again." and redirects to the page with a full
    request, so the plug puts an open cart in the session. Rule 9 backs it: every function that
    writes cart contents refuses a closed cart with `{:error, :cart_closed}`, so a write that
    gets past the page (a race, or a handler added without the hook) fails loudly instead of
    landing in a cart nobody reads again.

Rule 12 checks before the event rather than re-resolving the cart in it. A LiveView cannot write
the session, so re-running `get_or_create_open_cart/1` from an event would create an open cart
the session does not name. The next request would replace it, and the write would be lost the
same way. The full request is what moves the session on.

## The roots

| Page | Root | Parts | Open-cart guard |
|---|---|---|---|
| `CartLive.Index` | `parts(session)` via `CartSession.editor_parts/4` | `shop` (storefront, from `"cart_id"`), `pricing`, `undo` (stream `:items`, reprice `assign_summary/1`) | every event, reloads `/cart` |
| `PortalLive.Index` | `parts(session)` via `CartSession.editor_parts/4` | `shop` (portal, from `"portal_cart_id"`), `pricing`, `undo` (stream `:lines`, reprice `assign_summary/1`) | every event, reloads `/portal` |
| `CheckoutLive.Index` | `parts(session)` | `shop` (storefront), `pricing`, `success_url` | every event, reloads `/cart` |
| `ProductLive.Index` | `parts(session)` | `shop` (storefront) | `add_to_cart` only, reloads `/products` |
| `ProductLive.Show` | `parts()` | `channel` (storefront, for the stock badge) | none: no cart |
| `CheckoutLive.Success` | none | it composes nothing | none |

`pricing` is a function of the cart because the promo code and shipping method it is configured
by change while the page is open. The product list guards only Add to cart so that a stale
shopper session never blocks a staff delete. `ProductLive.FormComponent`'s events go to the
component, which the hook does not see, and write no cart. `PortalLive.Index` keeps V58's mount
check as well: reaching the portal by live navigation after Submitted is an ordinary path, and it
redirects before showing the completed draft.

`Plugs.EnsureCart` has no root. It builds one shop in one line of `call/2`.

## The guard audit

Every handler in V58 that writes to a cart wrote through the shop its root built at mount. None
re-read the session. V0 does the same with `socket.assigns.cart_id`. They are all reachable with
a stale id when the cart closes in another tab or after live navigation.

| Page | Events that write the session cart | Writer (now refusing a closed cart) |
|---|---|---|
| `CartLive.Index` | `update_quantity`, `toggle_gift_wrap`, `save_for_later`, `move_to_cart`, `undo_remove`, `toggle_wishlist`, `remove_from_wishlist`, `add_wishlisted_to_cart`, `apply_promo`, `select_shipping`; `remove_item` and `checkout` through `UndoRemoval.finalize` | `change_quantity`, `toggle_gift_wrap`, `save_for_later`, `move_to_cart`, `restore_item`, `toggle_wishlist`, `remove_from_wishlist`, `move_wishlist_item_to_cart`, `apply_promo_code`, `select_shipping_method`, `delete_item` |
| `PortalLive.Index` | `add_to_order`, `update_line`, `undo_remove`, `select_shipping`, `submit_order`; `remove_line` and `review` through `finalize` | `add_item`, `update_item`, `restore_item`, `select_shipping_method`, `Orders.submit_portal_order`, `delete_item` |
| `CheckoutLive.Index` | `save_address`; `pay`, whose async result calls `Orders.complete_checkout` | `save_address`, `Orders.complete_checkout` |
| `ProductLive.Index` | `add_to_cart` | `add_item` |

Each `ShoppingCart` writer has a context test that it refuses a completed cart and leaves the
cart as it was (14 tests, `describe "a closed cart"`). The two `Orders` functions refuse it
too, with a test each. Without that, a stale checkout tab could order the same cart twice. That
goes a little past the brief's "every `ShoppingCart` function", so it is a judgement call.
`set_cart_status/2` is not guarded: it is how a cart closes.

Two paths are not events, and the hook does not cover them. The undo timer's
`{:undo_expired, id}` deletes the pending item through `UndoRemoval.finalize/1`, which accepts
`{:error, :cart_closed}`: a cart ordered meanwhile was ordered with that item, so it should stay.
Checkout's `handle_async` completes the order after the `pay` event passed the guard. If the cart
closes in that window, `complete_checkout` refuses, and the page shows its existing "Some items
are out of stock" message, which is wrong for that case. The check and the write are also not
atomic: a cart completed between `cart_closed?/1` and the update still takes the write. Closing
that race would need a row lock in every writer. Neither race is on a path a test or the change
run reached.

## Layer map

| Layer | Peers may call each other | Modules |
|---|---|---|
| app | yes | LiveViews, `ShopComponents`, `UndoRemoval`, `CartSession`, `Plugs.EnsureCart`, `Router`, `PageController`, `PageHTML`, `Layouts`, `Calibration`, `GoodDealWeb` |
| contexts | no | `Catalog`, `ShoppingCart`, `Orders`, `Payments` |
| domain | no | `GoodDeal.Domain.{Pricing, ShippingMethod, VolumeTier, PromoCode, StockStatus}` |
| platform | yes | `Repo`, `Mailer`, `ProductEvents`, `Channel`, `Shop`, the Ecto schemas, `Payments.Provider` and `InProcessProvider`, `GoodDeal` |

`CartSession` now calls `ShoppingCart.cart_closed?/1` and `Phoenix.LiveView.attach_hook/4`, both
lower. Through `editor_parts/4` it also calls `Calibration` and builds `%UndoRemoval{}`, both app-layer
peers, which the app layer allows. No module moved layer.

## What changed from V58

| V58 | V59 | Rule |
|---|---|---|
| `CartSession.shop(channel, cart_id)` | `CartSession.shop(channel, overrides)`, `cart_id:` required by `struct!/2` | 11 |
| `Calibration.pricing(channel, cart)` built a `%Pricing{}` literal | `Calibration.pricing(channel, cart, overrides \\ [])` through `struct!/2` | 11 |
| fixture `shop(cart_id, channel \\ :storefront)` | `defdelegate shop(channel, overrides), to: GoodDealWeb.CartSession`; its call sites now read `shop(:storefront, cart_id: cart.id)` | 11 |
| LiveView events wrote to the mount-time cart whatever its status | each root's `mount` attaches `CartSession.guard_open_cart/4` | 12 |
| `ShoppingCart` writers wrote to any cart | they refuse a closed cart with `{:error, :cart_closed}`; new `cart_closed?/1` | 9, 12 |
| `Orders.complete_checkout/2`, `submit_portal_order/3` placed an order on a completed cart | they refuse it with `{:error, :cart_closed}` | 9, 12 |
| `UndoRemoval.finalize/1` matched `:ok` from `delete_item/1` | it also accepts `{:error, :cart_closed}` | 12 |
| `%UndoRemoval{stream:, window_ms:}`; `remove(socket, undo, item)`, and each page repriced after `remove` and `undo` | `%UndoRemoval{stream:, window_ms:, shop:, reprice:}`; `remove(socket, undo, item_id)` and `undo/2` reprice through `undo.reprice` | 7 (R7) |
| cart and portal roots each built shop, pricing and undo | both call `CartSession.editor_parts(session, channel, stream, reprice)` | 7 (R7), 10 |

Behaviour through the pages is V58's on every path where the session cart is open. All 151 of
V58's tests pass, and only builder calls in them changed. The one change in behaviour is the one
rule 12 asks for: an event on a page whose cart has closed now reloads with a flash, where V58
wrote into the closed cart.

## Removing the last clone

V58 left one R7 clone, which made `--strict` report R7 as not met: the `remove`/`undo` handler
pair in `CartLive` and `PortalLive`, 34 nodes. Each handler looked up the item, called
`UndoRemoval` with its own config and then repriced with its own `assign_summary/1`. That
repricing is part of deferred removal, so it moved into `UndoRemoval`. `%UndoRemoval{}` now
also enforces `shop` (whose items it removes) and `reprice` (the page's repricing function).
`remove(socket, undo, item_id)` looks the item up and reprices, and `undo/2` reprices, including
when nothing is pending, as the handlers did before. The handlers are now one call each.

With the handlers gone from the comparison, the linter found the two roots alike instead (28
nodes): a shop, pricing and undo, each configured with its own channel and stream. V58's
DESIGN.md called that what a root is for. It is still one concept written twice, so both roots
now compose `CartSession.editor_parts/4`, configured with channel, stream and reprice where the
root sits. A short-lived `UndoRemoval.new/4` builder between them was a pass-through with one
caller, so `editor_parts/4` writes the struct with all four enforced keys itself. It is the only
place that builds one, and no test does. Nothing was renamed or reordered to get under the clone
threshold.

Behaviour is unchanged. The undo window is still read once, when the page mounts. Every test
passes unchanged, including the undo, expiry and reprice tests on both pages.

## Tests

V58 had 151 tests; V59 has 175.

- `ShoppingCartTest`, `describe "a closed cart"`: `cart_closed?/1`, then one test per writer
  (`add_item`, `update_item`, `change_quantity`, `toggle_gift_wrap`, `save_for_later`,
  `move_to_cart`, `restore_item`, `delete_item`, `toggle_wishlist`, `remove_from_wishlist`,
  `move_wishlist_item_to_cart`, `apply_promo_code`, `select_shipping_method`, `save_address`).
  Each asserts `{:error, :cart_closed}` and, where there is state to check, that it is unchanged.
- `OrdersTest`: `complete_checkout/2` and `submit_portal_order/3` refuse a completed cart.
- One stale-cart test per guarded page: the cart page, the portal and checkout each complete the
  cart under an open LiveView, fire an event and assert the redirect and an untouched cart. The
  product list asserts the flash after the redirect, a new session cart and an empty old one, and
  that a staff delete still works with a closed session cart.
- `CalibrationTest`: `pricing/3` takes an override. New `CartSessionTest`: `shop/2` takes
  `cart_id:` and refuses a missing or unknown key.
- Changed: builder calls only, `shop(id)` to `shop(:storefront, cart_id: id)` and
  `shop(id, :portal)` to `shop(:portal, cart_id: id)`, and one `import ..., only: [shop: 2]`.

## Cost

- Production lines (`lib/**/*.ex`) 3,054 to 3,129 (+75). `ShoppingCart` 213 to 243, `CartSession`
  18 to 64, `Orders` 116 to 121, `Calibration` 74 to 77, `ProductLive.Index` 72 to 75,
  `UndoRemoval` 60 to 65 and `CheckoutLive.Index` 136 to 137. `CartLive.Index` went from 249 to
  240 and `PortalLive.Index` from 207 to 198, since their roots and undo handlers shrank.
- Test lines 2,062 to 2,353 (+291): about 130 for the closed-cart context tests, 45 in
  `OrdersTest`, about 80 across the four LiveView files, 21 for the builders. The rest is the longer
  `shop(:storefront, cart_id: …)` calls, which `mix format` wrapped in places.

## Lint checks

`lint.exs` is V58's apart from its path comment, with the same layer map and the same checks off
(`r9`, `r10`, `r10_aggregate`, `r11`, `r11_share`, `ports`, `ports_unwired`, `ports_computed`,
`wiring_closure`, `hops`, `vocabulary`, `subcomponent`), because the form adopts no ports,
wiring, features or composition-only pages. V58's DESIGN.md gives the reason for each. There are
no `ala:accept` lines. The result is the same at every tier:
`by_rule=%{app_share: 1, module_avg: 1, public_surface: 1}`, score 100, with 225 functions
(V58: 214). There is no `clone` finding, and under `strict: true` R7 is `:met`. V58 had R7
`:not_met` from its one clone. All three remaining findings are reported only and never scored.
`public_surface` notes `ShoppingCart`'s 26 public functions, one more than V58 for
`cart_closed?/1`.
