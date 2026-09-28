# V40: Circuit instances

The same storefront and B2B portal as V39 (the V35 requirements), built the other way the toys
pointed at: each page builds a **circuit** of instances at mount and the template places **UI
instances** (LiveComponents) that own their events. No browser event is routed by the page.

**Score:** `ala_lint` 98/A default, 97/A strict, 96/A super-strict on the family layer map
(V39: 97/97/96; V35: 93/93/91; re-scored 2026-09-29). **83 tests, 0 failures.**

## The shape

- **Features** are the V39 modules unchanged in kind (`step(state, payload) :: {state, outputs}`),
  with three inputs added: `load/2` (the persisted rows arrive), `Cart.line/2` (hand a line out to
  whoever is wired), `Cart.request_checkout/2` (the aggregate goes out to be checked and charged).
  `Checkout` takes its stock source as configuration (`stock_levels: &Products.stock_levels/1`)
  instead of having the page compose stock in.
- **The port** (`ZeroCoupled.Ports.Step`) is a protocol: `push(step, {input, payload})` returns
  `{:emit, [{port, payload}], step}` or `{:quiet, step}`.
- **Paradigms** (`lib/zero_coupled/paradigms/`, no LiveView): `Circuit` (parts plus wires from
  `{instance, port}` to `{instance, input}`; pushing delivers depth first and returns unwired
  outputs as the edge), `Adapter` (makes a feature module a Step: the input name is the function),
  `Via` (a transform), `FromStore` (a source), and the sinks `ToStream`, `ToComponent`,
  `ToAssign`, `ToForm`, `ToFlash`, `ToStore`, `ToTimer`, `ToPatch`, `ToAsync`, `ToRedirect`. A sink
  emits its effect on port `:ui`.
- **The Runner** (`lib/zero_coupled_web/paradigms/runner.ex`, 62 lines) feeds the circuit in the
  socket and lands `:ui` effects as LiveView calls. Timers and async jobs come back as
  `{:feed, instance, data}` messages that `feed_message/2` returns to the circuit, so a page has
  one `handle_info` clause for all of them and one `handle_async` for all jobs.
- **UI instances** (`lib/zero_coupled_web/live/cart_live/instances.ex`, `portal_live/instances.ex`)
  own their streams and their `handle_event`s; each event is `Emitter.feed(socket, :cart,
  {:remove, ...})`, a push into a named input. Rows come back to them by `ToComponent`
  (`send_update` with a `change`).
- **The page** builds the circuit in `circuit/1` (parts, then wires) and places the instances in
  its template. `CartPage` has no `handle_event` at all.

Loading is a wire like any other: `{:lines, :loaded} -> {:cart, :load}`, pushed from mount by
`Runner.feed(:lines, {:load, cart_id})`, so the page never holds the rows.

## What it costs

- **Two message hops.** A click goes instance → page (`{:feed, ...}`) → circuit → instance
  (`send_update`). The tests settle a page with two renders after each action and poll for async
  results (`settle/1`, `eventually/3` in `test/zero_coupled_web/live/cart_live_test.exs`). V39's
  tests read the html a click returns.
- **More parts.** The cart circuit names 38 instances and 41 wires; V39's bindings map has 27
  entries and 17 one-line event handlers. Every flash text, assign and stream is an instance with a name, which is what makes
  the wiring read as a diagram and also what makes it long.
- **The sinks are a vocabulary to learn**, as the Binder's binding kinds are in V39. Here the
  vocabulary is a set of small structs implementing one protocol; adding a kind is a new module,
  not a new clause in the Binder.

## Running

```bash
mix deps.get
mix test
mix phx.server   # http://localhost:4000/cart and /portal
```

## Known departures and judgement calls

- `if connected?(socket), do: Broadcast.subscribe()` in both mounts, as in V39.
- The two pages' shipping rates repeat (R5), as in V39.
- `OrderPanel` and `PoForm` call `PortalView.summary/1` for the totals block: a UI instance using
  a page-owned component, sideways in the application layer.
- `CartControls` is one component rendered twice (`part: :top` for the banner and tabs,
  `part: :bottom` for the totals, shipping, promo and checkout button) so that both halves' events
  have one owner.
- The product pages are V35's, untouched.
