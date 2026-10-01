# V39-max: Bound ports, taken to 100

V39 (bound ports) changed until the full ALA Checklist, walked by hand, finds nothing to deduct. The
storefront and B2B portal as in V39–V42: features are `{state, outputs}` functions held in the page's
assigns, and each page's whole design is one map, `bindings/1`. Every step runs in the page process.
Blog post: [V39-max](https://getdown.dev/blog/intro-to-v39-max/).

**Score:** full checklist by hand **100** (V39 was 88). `ala_lint` 100/A default, 100/A strict,
99/A super-strict. **89 tests, 0 failures.** Familiarity 3 of 5.

## The shape

```elixir
def bindings(cart_id) do
  %{
    {:page, :mounted} => [
      {:via, &Carts.list_items/1, [{:input, :cart, &Cart.load/2}]},
      {:input, :checkout, &Checkout.show_form/2}
    ],
    {:cart, :checkout_requested} => [{:input, :checkout, &Checkout.pay/2}],
    {:checkout, :ready_to_pay} => [{:async, :payment, %StartPayment{...}}],
    {:checkout, :done} => [{:call, %PlaceOrder{...}}, :redirect],
    ...
  }
end
```

A binding's callee is a named function or a configured domain instance implementing the
`ZeroCoupled.Ports.Call` protocol (`AddLine`, `PlaceOrder`, `StartPayment`).

## What changed from V39

- No page helpers: store work and the payment call are configured domain instances the bindings name.
- No handler builds an input from assigns: `pay`, `toggle_wishlist`, `start_checkout` and `go_review`
  each run one feature input whose output carries what the next feature needs.
- Mount is an event on the diagram (`{:page, :mounted}`), so it doesn't hand a store's result to a feature.
- No silent drops: each page lists `features/0` and `grounded/0`, and `wiring_test.exs` checks every
  declared output is bound or grounded and every binding names a declared port.
- Timer binding kinds are `start_timer`/`stop_timer` on Undo's facts; outputs are facts throughout.
- Views only place parts: `ZeroCoupled.Catalog.Parts` and `Panes` hold the comparisons; every word
  comes from the page.
- The shared fixes V41-max has (configuration once, `StoreConfig`, `CartSession`, texts from the page).

## Run it

```bash
cd v39-max
mix deps.get
mix test
```
