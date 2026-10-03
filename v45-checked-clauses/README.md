# V45: Checked clauses

The design for a full ALA Checklist score with zero message hops, a codebase no larger than the other
full variants, and wiring that is both safe and familiar. It starts from V38-max: features as
`{state, outputs}` values in the page's assigns, and one private `wire/3` clause per feature port as
the page's wiring. Blog post: [V45, checked clauses](https://getdown.dev/blog/intro-to-v45-checked-clauses/).

**Score:** full checklist by hand **100**. `ala_lint` 100/A default, 100/A strict, 99/A super-strict.
**116 tests, 0 failures**, including the storefront and portal acceptance tests every full variant
shares. Familiarity 4 of 5. Zero message hops on the cart and portal pages.

## What it adds to V38-max

- **Named instances.** The page keeps its store-work instances (`AddLine`, `Charge`, `SettleOrder`,
  `PlaceOrder`) in one `@instances` map, and a clause names the one it wants:
  `Steps.feed(:cart, &Cart.receive/2, {:add_line, &AddLine.run/2}, product, &wire/3)`. No clause reads
  `s.assigns`, and a wrong name fails in the runner with the name in the message.
- **A one-line coverage test.** `GoodDealWeb.Paradigms.Wiring.gaps/1` reads a page's own source (from its
  compile info) and compares its `wire/3` heads with every port its features declare:
  `assert Wiring.gaps(CartLive.Show) == %{unwired: [], unknown: []}`.
- **An optional compile-time check.** `use GoodDealWeb.Paradigms.Wiring` on a page records each `wire/3`
  head as it compiles and fails the build on a gap. It's off by default: the test plus
  `ala_lint --strict` (which scores declared-port drift) give the same safety without a macro to learn.

## Run it

```bash
cd v45-checked-clauses
mix deps.get
mix test
```
