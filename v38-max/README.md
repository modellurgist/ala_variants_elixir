# V38-max: Lint-guided, taken to 100

V38 kept its cart page a conventional LiveView, logic and all. V38-max is what that page becomes when
the full ALA Checklist, walked by hand, finds nothing to deduct: still one plain LiveView module, with no
bindings map, route table or LiveComponent, but now it only wires. Blog post:
[V38-max](https://getdown.dev/blog/intro-to-v38-max/).

**Score:** full checklist by hand **100** (V38 was 91). `ala_lint` 99/A default, 99/A strict,
99/A super-strict. **110 tests, 0 failures.** Familiarity 4 of 5.

## The shape

Two features, `GoodDeal.Features.Cart` and `GoodDeal.Features.Checkout`, are `{state, outputs}`
functions held in the page's assigns. Each browser event runs one step; `Steps.run/4` folds every output
through the page's `land/3`, one clause per port:

```elixir
defp land(s, :cart, {:rows, change}), do: Steps.stream_change(s, :cart_items, change)
defp land(s, :cart, {:summary, summary}), do: assign(s, :summary, summary)
defp land(s, :cart, {:checkout_requested, order}), do: run(s, :checkout, &Checkout.pay(&1, order))
defp land(s, :checkout, {:blocked, reason}), do: put_flash(s, :error, @blocked[reason])
...
```

There is no catch-all clause. `test/good_deal_web/live/wiring_test.exs` reads the clause heads and checks
every declared port has one, and every clause names a declared port.

## What changed from V38

- `CartState`, `CheckoutState`, `UIState` and `Helpers` became two features and `Domain.Lines`.
- The store's rules are configured instances: `Shipping`, `Promo`, `GiftWrap`, `Inventory`, `Checkout`
  (currency); `Charge`, `SettleOrder` and `AddLine` do the I/O the page and product index used to.
- The markup places generic `GoodDealWeb.Parts` and `Domain.StockIndicator`; every word is in the page's
  `@texts`.
- `on_mount` subscribes; the product form's messages are a map.

## Run it

```bash
cd v38-max
mix deps.get
mix test
```
