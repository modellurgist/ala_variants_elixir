# V46: Feature stories

V45 with Spray's Features layer. Each page is a composition of user stories: modules that instantiate
and configure domain abstractions, wire them to each other and to their own view, and have ports of
their own. The page wires the stories together. Blog post:
[V46, feature stories](https://getdown.dev/blog/intro-to-v46-feature-stories/).

**Score:** full checklist by hand **100** under the 2026-10-02 stricter readings. `ala_lint` 100/A
default, 100/A strict (10 of 10 checked rules met), 99/A super-strict. **124 tests, 0 failures**,
including the storefront and portal acceptance tests every full variant shares. Familiarity 3 of 5.
Zero message hops.

## What it changes from V45

- **Stories (Spray's features).** "Each feature creates instances of domain abstractions, configures
  the instances with feature specific details, and connects them together as needed to express the
  feature or user story" (§2.2). The cart page composes `EditCart`, `UndoRemoval`, `SaveForLater`,
  `KeepWishlist` and `CheckOut`; the portal composes `EditOrder`, `BrowseCatalog`, `SubmitOrder` and the
  same `UndoRemoval`. Each story holds its parts' wiring (`wire/4`, one clause per part port), its
  inputs (`input/4`), its browser events (`event/4`) and its view (a function component built from
  domain UI components, §7.14).
- **The page wires stories, not parts.** The cart page's `wire/3` has 15 clauses: 12 link one story to
  another, and 3 land counts and the tab on the page. V45 had nine cross-feature wires; the other three
  were hidden in shared page assigns (`@summary`, `@wishlist_ids`) or an event the checkout's view sent
  to the cart, and are explicit now. The portal's has 7. Browser events go to the story whose view
  emits them.
- **A runner for stories** (`Paradigms.Story`): `run`, `feed`, `send_out`, `send_out_answer`, `show`,
  and timers and async tasks that report back to the story's own input ports, so the page needs one
  generic clause for each and knows no timer or task name. `Sinks` holds the LiveView landing points
  (streams, patch, timers) both runners use.
- **State, not Features.** The coded state modules (`Cart`, `Undo`, `Checkout`, …) are stateful domain
  abstractions in Spray's terms, so they're `GoodDeal.State.*` now.
- **A record form instead of `FormComponent`.** A generic `record_form` domain UI component (fields,
  words and event names as attributes, no state) and a `RecordEdit` state (open, validate, submit,
  saved) that the product pages wire to `SaveProduct`.
- **Coverage, one level in.** `Wiring.gaps/1` checks each page's clauses against its stories' output
  ports; `Wiring.story_gaps/1` checks each story's `wire/4`, `input/4` and `event/4` heads against its
  parts' ports, its own inputs and its view's events; `Wiring.event_clashes/1` checks no two stories on
  a page claim one event.

## Run it

```bash
cd v46-feature-stories
mix deps.get
mix test
```
