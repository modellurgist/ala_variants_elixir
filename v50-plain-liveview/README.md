# V50: Plain LiveView

V48 without its one piece of unfamiliar vocabulary: the test of whether a full ALA Checklist score can
be reached at familiarity 5 with no relays between components. Blog post:
[V50, plain LiveView](https://getdown.dev/blog/intro-to-v50-plain-liveview/).

**Score:** full checklist by hand **100**. `ala_lint` 100/A at every tier (10 of 10 checked rules met
under `--strict`). **118 tests, 0 failures.** Familiarity 5 of 5 (judgement). No LiveComponents, so no
relays between them; every update runs inside one `handle_event`, and only the payment is a task.

## What it changes from V48

- **No named instances.** The configured store-work instances (`AddLine`, `Charge`, `SettleOrder`,
  `PlaceOrder`) are plain assigns, and a clause names the call it makes:
  `Steps.feed(:cart, &Cart.receive/2, &AddLine.run(s.assigns.add_line, &1), product, &wire/3)`.
- **LiveView's own API for the rest.** The payment is `start_async(s, :payment, fn -> Charge.call(charge, payment) end)`,
  its outcome routed by `handle_async/3`; settling the order is a plain call before `push_navigate`.
- **`Steps` is `run/4` and `feed/6`** (plus the stream, patch and timer landing points). `call`,
  `async` and the instance lookup are gone.

What it gives up: a misnamed instance is no longer a loud "no configured instance" error, and clauses
read configured instances from assigns again (as V38-max and V49 do). Store work stays synchronous, as
in V48.

## Run it

```bash
cd v50-plain-liveview
mix deps.get
mix test
```
