# V52: ALA Light

V51B (`../v51b-shared-story`, one `EditLines` story edited by both the cart and the order, each page
with its own pricing story) under the ALA Light rule set of `../../ala_lab/docs/Q-ala-light-subsets.md`,
subset 2: layers and a composition page, with logic allowed on the page as pure functions. The
change sequence of 2026-10-21 (`../../ala_lab/docs/change-cost-sequence-2026-10-21.md`) found ALA's
cost per change came largely from R11 applied as a hard gate and from the 12-function limit, and
its benefit from layering (R1, R3) and the composition reading as the requirements (R8); this
variant keeps the second and relaxes the first. V51B's README says V51B was first called V52 while
the running trace was built there; that name is retired, and this V52 is a different variant.

What is relaxed: R11 (composition only) is advice, not a score. An application-specific pure
function may be written on a page or in a story and handed to a part as configuration or called
from a `wire/3` clause, and a branch or loop that would otherwise become a one-use abstraction may
stay on the page; R7 (earns its existence) then decides. The public-surface limit is reported only
(already the linter's default) and R10 reads lifecycle by identity key as the identity's business
(already the checklist's reading). What is not relaxed: the wiring reads top to bottom (R8),
literals live at the composition (R3), a domain part never knows one page's words (R3, R6), and the
page still doesn't compute between `wire/3` clauses with assigns used as scratch. Spray's basis is
§6.28.1 and §6.28.3, the application-specific function kept in the application layer.

What changed in the code: three one-page rules folded back into their pages as pure functions, the
Light shape. `Domain.VolumeTier` (16 lines) is `volume_tier/1` on the portal page (210 → 217 lines);
`Domain.CalculateGiftWrapCost` (9 lines) is `&(&1 * Catalog.gift_wrap_cents())` and
`Domain.ValidatePromo` (19 lines) is `validate_promo/1`, both on the cart page (325 → 333 lines).
`OrderTotals`, `CartTotals` and `Promo` now call the function they are configured with
(`pricing.volume.(subtotal)`, `wrap.(count)`, `codes.(code)`) instead of a named module's `call/2`;
otherwise their interfaces are as they were (53 → 52, 77 → 76, 30 → 28 lines). The three domain
unit tests moved: the parts' tests configure them with inline functions, and the pages' tests cover
the folded rules (a code in any case with spaces around it, the wrap price in the summary, no tier
below the first threshold). `lint.exs` passes `checks: %{r11: :advisory}`. `StockIndicator` stays a
part: it is a concept, not a one-page rule. Nothing else moved.

**Score:** full checklist by hand **100**, with R11 read as advice. `ala_lint` with `lint.exs`'s layer
map: **100/A at every tier**, R11 advisory, four R11 findings reported, one or more on each fold:
two on the portal's `volume_tier/1`, one on the cart's `validate_promo/1`, and one on the cart's
`mount/3` for the gift-wrap capture `&(&1 * …)` it builds (`by_rule=%{unassigned: 1, r11: 4,
module_avg: 1, r11_share: 1}`, 563 functions, the same line at normal, strict and super-strict). The
last two were invisible until 2026-10-22: the linter read a `case` with a `nil ->` arm as routing and
didn't walk shorthand functions for arithmetic.
**150 tests, 0 failures** (V51B's 152, less the three
domain-module tests, plus one page test), every declared output routed under the suite.
Familiarity 4 of 5 (judgement), as V51B.

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
cd v52-ala-light
mix deps.get
mix test
cd ../../ala_lint_elixir && mix run ../ala_variants_elixir/v52-ala-light/lint.exs   # every tier, with the layer map
```
