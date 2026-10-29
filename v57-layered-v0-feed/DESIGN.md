# V57 design: layered V0 with a live-update paradigm (ALA form 2)

Form 1c (V56) kept ALA's measured benefits at 1.12× V0's cost over S01–S06
(`ala_lab/docs/change-cost-form1-2026-10-24.md`). Form 2 adds the one piece of ALA's
programming-paradigms layer that the strict variants found worth building: a generic feed of
changes made elsewhere (checklist, "A live subscription port"; V50, V51 and V51B built it as
`Paradigms.ChangeFeed`). The later steps of the change sequence (stock caps, live price changes)
are where it should pay. V57 is V56 with every live path moved onto it and nothing else changed.

## The ten rules

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

One paradigm, added in V57:

10. **A change made elsewhere reaches an open page only through the feed.** One platform-layer
    paradigm module, `GoodDeal.ChangeFeed`, owns the fact format and the transport (PubSub). A
    writer (a context, after its transaction commits) publishes a fact keyed by identity: a kind,
    the identity and the changed values (`:stock` for product 12 is `%{stock: 3}`), never a
    rendered view or a whole struct the page must interpret. A page subscribes once, in
    `mount/3`, declaring the kinds it listens to and what each does. The paradigm is generic: it
    knows no product, cart or page. No page or context keeps its own hand-built channel.

    As a convention for future changes: a new kind of outside change is a new fact kind published
    by the context that writes it, and a page that should show it adds one entry to its
    subscription map.

## The paradigm

`GoodDeal.ChangeFeed`, 39 lines, platform layer.

| Function | For | What it does |
|---|---|---|
| `publish(kind, id, values)` | writers | broadcasts `%ChangeFeed{kind, id, values}` on the kind's topic. `kind` must be an atom and `values` a map |
| `subscribe(socket, %{kind => (fact, socket -> socket)})` | pages, once in `mount/3` | when connected, subscribes to each declared kind's topic and attaches one `handle_info` hook that hands each fact to its kind's function. Disconnected, it returns the socket unchanged |
| `listen(kinds)` | tests, and anything not a LiveView | subscribes the calling process to the kinds' topics; facts arrive as `%ChangeFeed{}` messages |
| `dispatch(handlers, message, socket)` | the hook (public so it can be unit-tested) | `{:halt, socket}` after a declared kind's function, `{:cont, socket}` for any other message, so a page's own `handle_info` clauses (`:undo_expired`, the form component's `:saved`) still run |

The fact format is the module's own struct, with all three keys enforced (rule 8). Each kind is
its own topic (`"change_feed:<kind>"`), so a page receives only what it declared and no page
needs a clause to ignore a kind. The hook halts on a fact, so a fact never reaches the page's
`handle_info`. A page's functions take the fact first and return the socket, so they read like
any other socket transform and can be local captures (`&refresh_product/2`) or a shared part
configured where it is placed (`&LiveProducts.refresh(&1, &2, :products)`).

### Fact kinds

Every kind today carries a product id. The values are the fields that changed, as written.

| Kind | Published by | Values |
|---|---|---|
| `:product_added` | `Catalog.create_product/1` | all of the product's catalog fields: `name`, `description`, `amount`, `stock`, `thumbnail` |
| `:details` | `Catalog.update_product/2`, when `name`, `description` or `thumbnail` changed | the changed ones of those |
| `:price` | `Catalog.update_product/2`, when `amount` changed | `%{amount: _}` |
| `:stock` | `Catalog.update_product/2`, when `stock` changed; `Orders.complete_checkout/2`, per product decremented | `%{stock: _}` |
| `:product_removed` | `Catalog.delete_product/1` | `%{}` |

`Catalog` derives the update kinds from the changeset's changes through one attribute,
`@fact_fields`, so one edit can publish up to three facts. A staff stock edit and a checkout
both publish `:stock`, so a page that listens only to stock (a stock cap, say) hears both.
That is the gap V50, V51 and V51B each found when they moved onto their feeds, closed here by
the fact kind rather than by a wire.

### `GoodDealWeb.LiveProducts`

Three pages show products in a stream: the product list, the portal catalog, and the cart's
wishlist tab. `LiveProducts` (app layer, 23 lines) is the one part they place to keep such a
stream current: `add/3` builds the row from an added product's values (no read), `refresh/3`
re-reads the product by id and upserts it (skipping a product it can't read), and `drop/3`
deletes the row by id. A page names its stream when it places it. It exists because the product
list and the portal wrote the same three handlers (the linter's `clone` check found the two
subscription maps identical), and the cart's wishlist row was a fourth copy of `refresh`.

## The live paths, before and after

| # | Change made elsewhere | V56 | V57 |
|---|---|---|---|
| 1 | product created (`/products` form, or any `create_product/1`) | `Catalog` broadcast `{:product_created, product}`; `ProductLive.Index` and `PortalLive.Index` `stream_insert`ed it; `CartLive.Index` had a clause to ignore it | `:product_added`; the product list and the portal declare `&LiveProducts.add(&1, &2, :products)`; the cart doesn't declare the kind, so it never receives it |
| 2 | product edited (any field) | `{:product_updated, product}`; the product list upserted it; the portal upserted its catalog row and, for a product on the draft, re-read the line and repriced; the cart, for a product it shows, upserted the wishlist row, re-read the cart row and repriced | `:details`, `:price` and/or `:stock`, each mapped by every page to the function its `:product_updated` clause had become. Each page re-reads the product by id instead of using a broadcast struct |
| 3 | stock decremented by a checkout in another session | `Orders` broadcast `{:product_updated, product}` per product (the struct from `update_all`'s `select`) | `Orders` publishes `:stock` with `%{stock: n}` per product; same handlers as 2 |
| 4 | product deleted | `{:product_deleted, product}`; the product list and the portal deleted the row; the portal, for a draft line, re-listed the lines; the cart, for a product it shows, re-listed all three tabs | `:product_removed`; `LiveProducts.drop/3` deletes by id; the portal's and cart's re-listing as before |

Not live paths, and unchanged: the form component's `{FormComponent, {:saved, product}}` to its
own page (a change made on the page, not elsewhere; the page now gets the fact as well, and the
second upsert is a no-op), and `UndoRemoval`'s `{:undo_expired, id}` timer.

Removed as dead: `GoodDeal.ProductEvents` (21 lines), the three pages' `ProductEvents.subscribe()`
calls, seven `handle_info` clauses (among them the cart's clause ignoring created products) and
the cart's two-clause `handle_product_change/3`.

**Gaps.** Moving found no gap among the pages that were live. Two pages show product data and
were never live, in V0 or V56: `ProductLive.Show` (`/products/:id`, price and stock) and
`CheckoutLive.Index` (the total being paid). Under rule 10 each is a `subscribe` call plus a
handler (about five lines), not a one-line declaration, so they are left as they were. Checkout
not repricing before Pay is the shared S06 defect the change-cost run already notes. Changes to a
cart made in another tab of the same session (an add from `/products` while `/cart` is open) do
not reach the open cart either; no context publishes cart facts, in V56 or here.

## What changed from V56

| V56 | V57 | Rule |
|---|---|---|
| `GoodDeal.ProductEvents`: one topic, `{event, %Product{}}` | `GoodDeal.ChangeFeed`: one topic per kind, `%ChangeFeed{kind, id, values}` | 10 |
| `Catalog.create/update/delete_product` piped the result into `ProductEvents.broadcast/2` | each publishes after a successful write, `update_product/2` one fact per changed field group (`@fact_fields`) | 10 |
| `Orders.complete_checkout/2` broadcast the updated product struct | publishes `:stock` with the new level | 10 |
| pages subscribed with `ProductEvents.subscribe()` and matched `{event, product}` in `handle_info` | each calls `ChangeFeed.subscribe/2` once in `mount/3` with its map of kinds | 10 |
| — | `Catalog.get_product/1` (nil for a missing id), for pages that re-read a product a fact names | 10 |
| — | `GoodDealWeb.LiveProducts`, the shared product-stream handlers | 10, R7 |

Behaviour through the pages is V56's. Off them, two things differ. An update that changes nothing
publishes nothing, where V56 broadcast the unchanged product (pages re-rendered the same row). And
a page shows what the database holds when it handles the fact, where V56 showed the struct the
writer broadcast; the two differ only when a later write lands in between, and then V57 shows the
newer value.

## Tests

V56 had 149 tests; V57 has 156. What changed:

- Adapted to the new message shape (rule 10's break, test code that matched the old messages
  directly): catalog's `describe "broadcasts"` is now `describe "feed facts"`, subscribes with
  `ChangeFeed.listen/1` and matches `%ChangeFeed{}`. Its first test is renamed "create, update and
  delete publish facts keyed by the product's id" and asserts `:product_added`, `:stock` and
  `:product_removed`; "a failed update broadcasts nothing" refutes a `:details` fact where it
  refuted `:product_updated`. `complete_checkout/2`'s main test listens to `:stock` and asserts the
  fact for the new level where it asserted `{:product_updated, %{stock: 3}}`.
- No LiveView test changed. They drive changes through the contexts, so they moved with the code.
- Added: `test/good_deal/change_feed_test.exs` (5 unit tests, with made-up kinds and no product:
  listening receives only declared kinds; a fact needs an atom kind and a map; dispatch hands a
  declared fact to its function and halts; dispatch passes on undeclared kinds and other
  messages; a disconnected socket is unchanged and listens to nothing). Catalog: "an update
  publishes one fact per kind of field it changed". Product list: "a fact about a product this
  page cannot read leaves the list as it was", which pins `LiveProducts.refresh/3`'s nil branch;
  without it that branch was covered only by facts leaking in from other async tests.

## Cost

- Production lines (`lib/**/*.ex`) 2,994 to 3,047 (+53). `ChangeFeed` 39 and `LiveProducts` 23
  in, `ProductEvents` 21 out; `Catalog` 109 to 122; `PortalLive.Index` 194 to 193; `CartLive.Index`
  (236) and `ProductLive.Index` (63) the same length; `Orders` unchanged at 116.
- Test lines 2,068 to 2,138 (+70): the feed's unit tests (44), the catalog and page tests.
- Subscription maps are longer than the clauses they replace for the product list (five entries,
  three of them the same function) because an edit is three kinds. That is the price of a page
  that cares only about stock being able to say so.
- **A read per fact.** V56's pages rendered the broadcast struct. V57's facts carry only what
  changed, so a page whose stream row needs the whole product re-reads it: every open product
  list and portal re-reads once per `:details`, `:price` or `:stock` fact, store-wide (the cart
  only for products it shows, as before). An added product needs no read, since its fact carries
  every field.
- **Log noise in the test suite.** Topics are global, so in async tests a portal or product-list
  LiveView re-reads products named by other tests' facts. When its own test ends during such a
  read, Postgrex logs `disconnected: ... client #PID<...> exited`. Traced with a temporary print
  in `dispatch/3`: every case was `PortalLive.Index` handling a `:stock` fact. It shows in roughly
  half the runs, one or two lines; no test has failed from it. V56 logged none in three runs.
  Building added rows from the fact's values (above) made it rarer (before, it was one to three
  lines in every run); tracking which ids each page shows would remove it, at a few lines per
  page, and is not done.

## Layer map

| Layer | Peers may call each other | Modules |
|---|---|---|
| app | yes | LiveViews, `ShopComponents`, `UndoRemoval`, `LiveProducts`, `CartSession`, `Plugs.EnsureCart`, `Router`, `PageController`, `PageHTML`, `Layouts`, `Calibration`, `GoodDealWeb` |
| contexts | no | `Catalog`, `ShoppingCart`, `Orders`, `Payments` |
| domain | no | `GoodDeal.Domain.{Pricing, ShippingMethod, VolumeTier, PromoCode, StockStatus}` |
| platform | yes | `Repo`, `Mailer`, `ChangeFeed`, `Channel`, `Shop`, the Ecto schemas, `Payments.Provider` and `InProcessProvider`, `GoodDeal` |

`ChangeFeed` is platform because it is generic and both contexts and pages depend on it. It imports
`Phoenix.LiveView` for `attach_hook/4` and `connected?/1`, so the platform layer now depends on
LiveView as well as on `Phoenix.PubSub`.

V56's DESIGN.md (`../v56-layered-v0-honest/DESIGN.md`) has the structs, their enforced fields
and the guard audit; all of it still holds.

## Lint checks

`lint.exs` is V56's with `GoodDeal.ProductEvents` replaced by `GoodDeal.ChangeFeed` in the
platform layer and `GoodDealWeb.LiveProducts` added to the app layer. Check settings are V56's
(ports, wiring, features and composition-only checks off, for the reasons V56's DESIGN.md gives).
No `ala:accept` lines. Result, the same at every tier:
`by_rule=%{app_share: 1, clone: 1, module_avg: 1, public_surface: 1}`, score 100, 208 functions
(V56: 207). The findings are V56's: the `clone` is the cart's and portal's remove/undo handlers.
Before `LiveProducts`, a second `clone` flagged the product list's and the portal's subscription
maps.
