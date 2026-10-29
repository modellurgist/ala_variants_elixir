# V53: ALA ports only at variation points

V52 (`../v52-ala-light`, ALA Light: V51B with R11 read as advice) reshaped by subset 3 of
`../../ala_lab/docs/Q-ala-light-subsets.md`: ports only where a part is placed by two or more
compositions today, or is a paradigm. Everything else is called, and the page uses what it answers.
The 2026-10-22 change run (`../../ala_lab/docs/change-cost-light-2026-10-22.md`) found V52 no
cheaper than strict ALA because its dearest change still moved values along wires through parts
placed once. This variant removes those wires.

What stays wired: `DraftOrder` (both pages place it; it holds `EditLines`, `UndoRemoval` and the
cart and portal's `ChangeFeed`, which both pages used to place and wire to each other the same way),
`ChangeFeed` (a paradigm) and `RecordEdit` (both product pages). `CartLines` and `Undo` keep their ports inside those stories,
a judgement call explained in DESIGN.md. What folded: `PriceCart`, `CheckOut`, `SaveForLater` and
`KeepWishlist` into the cart page; `PriceOrder`, `BrowseCatalog` and `SubmitOrder` into the portal
page. The pages call `CartTotals`, `Promo`, `Checkout`, `SavedItems`, `Wishlist`, `PageUI`,
`OrderTotals`, `PortalCatalog` and `PortalSubmit` directly; none of them declares ports now. The
inventory, what changed and what it costs are in DESIGN.md.

**Status (2026-10-23).** **152 tests, 0 failures**, every declared output routed under the suite
(one part per page, `draft`, and `DraftOrder`'s three parts, checked the same way). No LiveView test
changed; the unit tests of the reshaped parts assert returned values. `mix compile
--warnings-as-errors` (dev and test), `mix format --check-formatted` and `mix credo --strict` clean.
`ala_lint` with `lint.exs`'s layer map: **100/A at every tier**, R11 advisory as in V52, with
`r11_calls: :wired_only` leaving out hand-offs into called parts
(`by_rule=%{unassigned: 1, r11: 17, app_share: 1, module_avg: 1, r11_share: 1}`, 452 functions), no
clone finding. The 17 R11 findings (25 without the option) are the page logic the rule asks for (a
`case` on what a call answers, a step change that patches the URL). The clone V53 first had (both pages' `mount/3` placing
the same three variation points the same way) is now `Stories.DraftOrder`; DESIGN.md has the
details. `lib/` is 5228 lines of `.ex`, from V52's 5644; the cart page is 529 lines (472
non-blank), the portal 292. Databases: `good_deal_v53_dev`, `good_deal_v53_test`.

## Inherited from V51B

*Since 2026-10-21:* outside change is a part. `Paradigms.ChangeFeed` (programming-paradigms layer) is
mounted by a page as `feed`, configured with a topic and the facts it wants, and wired like a story:
`feed.stock → edit_lines.stock` on the cart, `→ edit_lines.stock, catalog.stock` on the portal,
`feed.product`/`feed.stock` into the product list. A page that changes a product hands it to
`ChangeFeed.publish/2`: the checkout's settlement (`SettleOrder`'s `announce`) and both product pages'
saves. `Foundation.Broadcast`, `Paradigms.Subscribed` and the pages' `handle_info` clauses for
catalogue messages are gone. The move closed a gap: a staff stock edit at /products never reached
an open cart or portal, which ignored `:product_updated`; the product pages now publish `:stock`
with `:product`.

V51B's own history and what it changed from V51 are in `../v51b-shared-story/README.md`.

## Run it

```bash
cd v53-ala-variation-ports
mix deps.get
mix test
cd ../../ala_lint_elixir && mix run ../ala_variants_elixir/v53-ala-variation-ports/lint.exs   # every tier, with the layer map
```
