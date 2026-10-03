# V49: Plain components

V41-max without its route table: the test of whether a full ALA Checklist score can be reached at
familiarity 5. Feature panels are LiveComponents, the page's wiring is plain `handle_info` and
`handle_async` clauses, and everything the page calls is LiveView's own API. Blog post:
[V49, plain components](https://getdown.dev/blog/intro-to-v49-plain-components/).

**Score:** full checklist by hand **100** (99.5, the hop) under the 2026-10-02 readings. `ala_lint`
100/A default, 100/A strict (10 of 10 checked rules met), 99/A super-strict. **86 tests, 0 failures.**
Familiarity 5 of 5 (judgement). One message hop per cross-feature effect.

## What it changes from V41-max

- **No route table.** One `handle_info({:cart, :removed, item}, socket)` clause per port an instance
  sends, using `send_update`, `assign`, `put_flash` and `push_patch`. Clauses in one module meet R8.
- **Store work through LiveView's tasks.** Where an answer goes to another instance (adding a line,
  placing a portal order, a payment), the page starts a `start_async` task and `handle_async` sends
  the answer on, so the page never passes one abstraction's result into another. Adding a line is
  now asynchronous: the line appears a moment after the click.
- **Instances are named by the page.** Each panel sends `{name, port, payload}` under the `name`
  attribute the page gives it (`<.live_component module={Cart.Panel} id="cart" name={:cart} />`),
  instead of naming itself in its own code, a silent contract (R5) V41 and V41-max both had.
- **`OrderLines` emits `review`.** The panel used to build that output from its own assigns.
- **`State`, not `Features`, and a generic `RecordForm`** LiveComponent (a widget whose own state is the
  form being typed; the page saves through a task) instead of `FormComponent`.
- **Coverage from the source.** A test reads the page's `handle_info` clause heads and checks them
  against every port each placed instance sends, both ways.
- `Instance` is two functions: `step/3` and `send_port_output/3`.

## Run it

```bash
cd v49-plain-components
mix deps.get
mix test
```
