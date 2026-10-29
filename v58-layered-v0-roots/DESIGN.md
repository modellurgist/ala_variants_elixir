# V58 design: layered V0 with composition roots (ALA hybrid 1: form 1c + 3)

Form 1c (V56) ran ten changes at 1.07 times V0's cost, with strict ALA's breakage and the best
design score of the forms measured (`ala_lab/docs/change-cost-form1-2026-10-24.md`). Two costs
it carried were cheap to remove. A reader had to scan a page's handlers to learn which channel,
pricing and helpers it used, since each handler reached for `Calibration` or the session itself.
And its raw breakage count was dominated by fixture edits: a new required key or a changed
helper signature broke every test that built through the shared fixtures. V58 is V56 with the
two rules that address these (the first "hybrid form to measure next" in that document): a
composition root per page, from form 3, and test structs built through the app's own builders.
Behaviour through the pages is V56's.

## The eleven rules

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
   a test-owned `%Channel{}` and assert results through the rule's public function. Since V58
   they build it with `Calibration.channel/2`, overriding only the field the rule reads (rule 11).

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

Two added in V58:

10. **A composition root per page (form 3).** Each LiveView that uses configured parts has one
    private `parts/…` function, called from `mount`, that builds every part the page uses: the
    session's `%Shop{}` (which carries the channel's calibration), the pricing configured for
    that channel, and shared app-layer helpers with their settings (`%UndoRemoval{}`, with its
    stream and window). `mount` assigns the result once as `parts`. Handlers and templates read
    `parts.shop`, `parts.pricing.(cart)`, `parts.undo`, and never call `Calibration`,
    `CartSession` or `Application.fetch_env!` themselves. Nothing is wired: there are no ports
    and no output routing, and handlers still call the parts and use what they return. A new
    part, or a new setting for one, goes in the root.
11. **Tests build structs through the app's own builders.** Tests and fixtures build
    `%Channel{}` with `Calibration.channel/2`, `%Shop{}` with `CartSession.shop/2` (through the
    `shop/2` fixture, which delegates to it), and shipping methods by taking one from a
    calibrated channel and updating its fields. They never write a config or context struct
    literal. A test that needs a non-default value passes it as an override
    (`Calibration.channel(:portal, gift_wrap_price: 50)`), and `struct!/2` refuses an override
    that names no field. A new enforced key is then supplied once, in `Calibration`, and no test
    breaks for it.

## The roots

| Page | Root | Parts |
|---|---|---|
| `CartLive.Index` | `parts(session)` | `shop` (storefront, from the session's `"cart_id"`), `pricing` (`&Calibration.pricing(shop.channel, &1)`), `undo` (`%UndoRemoval{stream: :items, window_ms: Calibration.undo_window_ms()}`) |
| `PortalLive.Index` | `parts(session)` | `shop` (portal, from `"portal_cart_id"`), `pricing`, `undo` (stream `:lines`) |
| `CheckoutLive.Index` | `parts(session)` | `shop` (storefront), `pricing`, `success_url` (the URL handed to the payment provider, built in the `pay` handler in V56) |
| `ProductLive.Index` | `parts(session)` | `shop` (storefront; `add_to_cart` writes through it, the stock badge reads its channel) |
| `ProductLive.Show` | `parts()` | `channel` (storefront calibration, for the stock badge; the page needs no cart) |
| `CheckoutLive.Success` | none | it composes nothing: a heading and a link |

`pricing` is a function of the cart, not a `%Pricing{}`, because the promo code and shipping
method it is configured by change while the page is open. Each root builds its shop from the
mount `session` with `CartSession.session_shop/2`, which maps a channel to its session key.
V56 instead assigned both `shop` and `portal_shop` to every LiveView from an `on_mount` hook, so
which channel a page belonged to showed only in which assign its handlers read. The hook is
gone, and the router's `live_session` no longer names it. `ProductLive.FormComponent` is a
component, not a page, and takes nothing configured.

`Plugs.EnsureCart` has no `parts` function. It builds one `%Shop{}` from the key and channel the
router passes to `init/1`, in one line of `call/2`; a separate root would repeat that line.

The roots hold no `channel` key where they hold a shop: the shop already carries the channel
(rule 5), and templates read `@parts.shop.channel`. A first version held both, and the cart and
portal roots were then a 27-node clone (`ala_lint` flags 26 and up), which scored 99 at strict.
Moving the session-key lookup into `CartSession.session_shop/2` left the clone at 27 nodes;
dropping the duplicate key took it below the threshold. The
two roots are still alike, a shop, pricing and undo each configured with its own channel and
stream, which is what a root is for.

## The structs, schemas and guards

As V56 (its DESIGN.md has the tables), plus one struct: `GoodDealWeb.UndoRemoval` enforces
`stream` and `window_ms`. Neither has a correct default: the stream differs by page, and the window
is calibration (rule 8).

## Layer map

| Layer | Peers may call each other | Modules |
|---|---|---|
| app | yes | LiveViews, `ShopComponents`, `UndoRemoval`, `CartSession`, `Plugs.EnsureCart`, `Router`, `PageController`, `PageHTML`, `Layouts`, `Calibration`, `GoodDealWeb` (its `use` macros import `ShopComponents`) |
| contexts | no | `Catalog`, `ShoppingCart`, `Orders`, `Payments` |
| domain | no | `GoodDeal.Domain.{Pricing, ShippingMethod, VolumeTier, PromoCode, StockStatus}` |
| platform | yes | `Repo`, `Mailer`, `ProductEvents`, `Channel`, `Shop`, the Ecto schemas, `Payments.Provider` and `InProcessProvider`, `GoodDeal` |

## What changed from V56

| V56 | V58 | Rule |
|---|---|---|
| `CartSession.on_mount/4` assigned `shop` and `portal_shop` to every LiveView | gone; each page's root builds its own shop with the new `CartSession.session_shop/2` | 10 |
| handlers called `Calibration.pricing(shop.channel, cart)` (5 places) | they call `parts.pricing.(cart)` | 10 |
| `UndoRemoval.remove(socket, item, stream)`, `undo(socket, stream)`; the window read from app env inside `UndoRemoval` | `%UndoRemoval{stream:, window_ms:}` (both enforced) built in the root; `remove(socket, undo, item)`, `undo(socket, undo)` | 10 |
| the undo window read by `UndoRemoval` | `Calibration.undo_window_ms/0`, called by the roots | 10 |
| checkout built its success URL in the `pay` handler | `parts.success_url`, built in the root | 10 |
| templates read `@shop.channel`, `@portal_shop.channel`, `@shipping_methods` | `@parts.shop.channel`, `@parts.shop.channel.shipping_methods` (the `shipping_methods` assign is gone) | 10 |
| `Calibration.channel/1` | `Calibration.channel/2`, with overrides defaulting to `[]` | 11 |
| `test/support/fixtures/channel_fixtures.ex` built a literal neutral `%Channel{}` with `struct!/2` | deleted; rule tests call `Calibration.channel/2` with overrides | 11 |
| `ShippingMethodTest` wrote `%ShippingMethod{...}` literals | it takes `"standard"` from the storefront channel and updates `cost` and `free_above` | 11 |

Behaviour is unchanged. All 149 of V56's tests pass, and no assertion changed. Two more
differences show only off the pages' paths. The undo window is now read at mount rather than at
each removal, so a change to the app env while a page is open no longer reaches it. The success
URL is built at mount, with the same value.

## Tests

V56 had 149 tests; V58 has 151.

- `PromoCodeTest`, `StockStatusTest`, `VolumeTierTest`: their private `channel/0` calls
  `Calibration.channel(:storefront | :portal, field: value)` instead of `channel_fixture/1`.
  "no tiers, no discount" passes `volume_tiers: []` to the portal channel. The channels these
  tests now build are real ones with one value replaced, not V56's neutral test channel, so
  every other field carries a real value. None of the three rules reads those fields.
- `ShippingMethodTest`: `flat/0` and `capped/0` update the storefront's standard method
  (`free_above: nil` and `100`, `cost: 40`). Before, they were module-attribute literals.
- Added `test/good_deal_web/calibration_test.exs`: an override replaces one value and keeps the
  channel's others; an override naming no field raises `KeyError`.
- No LiveView or context test changed. They already built shops through the `shop/2` fixture,
  which delegates to `CartSession.shop/2`, and summaries through `Calibration.pricing/2`.

## Cost

- Production lines (`lib/**/*.ex`) 2,994 to 3,054 (+60). `CartLive.Index` 236 to 249,
  `PortalLive.Index` 194 to 207, `CheckoutLive.Index` 124 to 136, `ProductLive.Index` 63 to 72,
  `ProductLive.Show` 21 to 24, `UndoRemoval` 55 to 60, `Calibration` 64 to 74, `CartSession` 23 to
  18. The roots are 5 to 10 lines each; the rest is `parts.` prefixes that push handler lines past
  the formatter's width. The templates changed only in what they read.
- Test lines 2,068 to 2,062 (-6): the 23-line channel fixture went, the 16-line calibration test
  came, and the rule tests changed by a line or two each.

## Lint checks

`lint.exs` is V56's unchanged apart from its path comment. No module was added, so the layer map needed no change (`UndoRemoval`, `CartSession` and `Calibration` were already app-layer). It
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
`by_rule=%{app_share: 1, clone: 1, module_avg: 1, public_surface: 1}`, score 100, with 214
functions (V56: 207). The one `clone` is V56's: the `remove`/`undo` handlers in `CartLive` and
`PortalLive`, each calling `UndoRemoval` with its own config and then its own `assign_summary/1`.
It grew from 28 to 34 nodes because the handlers now read `socket.assigns.parts.undo` where V56
passed a stream name. `public_surface` still notes `ShoppingCart`'s 25 public functions.
