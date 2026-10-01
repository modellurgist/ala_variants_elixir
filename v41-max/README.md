# V41-max: Feature components, taken to 100

V41 (feature components) changed until the full ALA Checklist, walked by hand, finds nothing left
to deduct but the one message hop its design costs. The same storefront and B2B portal as V39–V42.
Blog post: [V41-max](https://getdown.dev/blog/intro-to-v41-max/).

**Score:** full checklist by hand **100** (99.5; V41 was 92). `ala_lint` 100/A default, 100/A strict,
99/A super-strict. **83 tests, 0 failures.** Familiarity 4 of 5.

## The shape

Each feature is a LiveComponent instance that holds its state, renders itself and runs its own events.
The page places and configures the instances, and one `@routes` map says where each instance's
announcement goes:

```elixir
@routes %{
  {:cart, :removed} => [pass: {Undo.Banner, "undo", :capture}],
  {:undo, :restored} => [pass: {Cart.Panel, "cart", :receive}, flash: {:info, "Item restored"}],
  {:checkout, :step} => [patch: @step_paths],
  ...
}
def handle_info({_name, _port, _payload} = a, socket), do: {:noreply, Instance.route(socket, @routes, a)}
```

## What changed from V41

- Checkout calls the aggregate's functions (`Cart.id/1`, `Cart.items/1`, `Cart.product_ids/1`).
- Configuration once, first: `StockStatus.new(low_at:)`, `CalculateShipping.new(rates)`,
  `BuildLineItems.new(currency:)`; the store's rates, words and numbers in `ZeroCoupledWeb.StoreConfig`;
  session keys in `ZeroCoupledWeb.CartSession`.
- Every label, message and validation text comes from the page (`t` and `messages` attributes).
- Outputs are facts: `changed`, `captured`/`restored`/`expired`, `ready_to_pay`.
- `announces/0` is derived from `ports/0` minus each panel's `@lands_only`; no pass-throughs.
- One route table per page (`Instance.route/3`, five target kinds) instead of a clause per wire.
- Generic `Panes` (`pane`, `only_on`, `tabs`) and `Domain.StockIndicator` take the template comparisons.

## Run it

```bash
cd v41-max
mix deps.get
mix test
```
