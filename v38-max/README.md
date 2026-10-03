# V38-max: Lint-guided, taken to 100

V38 kept its cart page a conventional LiveView, logic and all. V38-max is what that page becomes when
the full ALA Checklist, walked by hand, finds nothing to deduct: still one plain LiveView module, with no
bindings map, route table or LiveComponent, but now it only wires. Blog post:
[V38-max](https://getdown.dev/blog/intro-to-v38-max/).

**Score:** full checklist by hand **100** (V38 built out: 85). `ala_lint` 100/A default, 100/A strict,
99/A super-strict (2026-10-01 linter). **116 tests, 0 failures**, including the same storefront and portal
acceptance tests as V39-max. Familiarity 4 of 5.

## The shape

Built out on 2026-10-01 to the full storefront and portal requirements. The features (`Cart`, `Undo`,
`SavedItems`, `Wishlist`, `PageUI`, `Checkout`, `OrderLines`, `PortalCatalog`, `PortalSubmit`), the domain
rules and the generic components are V39-max's, reused unchanged apart from names, over V38's foundation.
Store work is V38-max's own configured instances: `Charge`, `SettleOrder`, `AddLine`, `PlaceOrder`.

Each page (`CartLive.Show`, `PortalLive.Show`) is one plain LiveView. Each browser event runs one feature
step; `Steps.run/4` folds every output through the page's `wire/3`, one clause per port (29 on the cart
page, 15 on the portal):

```elixir
defp wire(s, :cart, {:removed, item}), do: run(s, :undo, &Undo.capture(&1, item))
defp wire(s, :cart, {:checkout_requested, cart}), do: run(s, :checkout, &Checkout.pay(&1, cart))
defp wire(s, :checkout, {:step, step}), do: s |> assign(:step, step) |> Steps.patch(@step_paths, step)
```

There is no catch-all clause. `test/good_deal_web/live/wiring_test.exs` reads each page's clause heads and
checks every declared port has one, and every clause names a declared port.

## Run it

```bash
cd v38-max
mix deps.get
mix test
```
