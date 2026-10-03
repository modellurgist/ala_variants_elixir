# V47: Typed story maps

V39-max with Spray's Features layer, typed ports, and a diagram drawn from the value that runs. Each
page is a composition of user stories; each story's wiring is a bindings map, and the page's own map
links the stories. Every port has a type, and the whole composition is checked when the page mounts.
Blog post: [V47, typed story maps](https://getdown.dev/blog/intro-to-v47-typed-story-maps/).

**Score:** full checklist by hand **100** under the 2026-10-02 stricter readings. `ala_lint` 100/A
default, 100/A strict (10 of 10 checked rules met), 99/A super-strict. **95 tests, 0 failures**,
including the storefront and portal acceptance tests every full variant shares. Familiarity 3 of 5.
Zero message hops.

## What it changes from V39-max

- **Stories (Spray's features).** "Each feature creates instances of domain abstractions, configures
  the instances with feature specific details, and connects them together as needed to express the
  feature or user story" (§2.2). The stories are the same as V46's: `EditCart`, `UndoRemoval`,
  `SaveForLater`, `KeepWishlist` and `CheckOut` on the cart page; `EditOrder`, `BrowseCatalog`,
  `SubmitOrder` and the same `UndoRemoval` on the portal. Each has a `bindings` map (its diagram as a
  value), `event/4` clauses that decode browser events, and a view built from domain UI components.
- **The page is the root story.** Its `bindings/0` map has 16 entries on the cart page, nearly all
  links between stories (`{:edit_cart, :removed} => [{:to, :undo, :capture}]`), and 8 on the portal.
- **Typed ports, checked at mount.** Every port declares a type; `Ports.Call` instances declare which
  payload types they accept and what each answers (`AddLine`: `product → item`,
  `product_quantity → item_quantity`); a plain function's answer type is written in its binding.
  `Binder.mount/2` refuses a composition with a wire between two types, an output neither bound nor
  grounded, an unbound input, or an anonymous function in a binding.
- **A diagram drawn from what runs.** `Diagram.mermaid/1` draws the page's stories and links, and
  `Diagram.mermaid_story/2` one story's insides, from the same value the page mounts (below).
- **State, not Features**, and **a record form instead of `FormComponent`**, as in V46.
- **Timers and tasks report to the story's own inputs**, so a page has one generic clause for each.

## The cart page, drawn from its composition

```mermaid
flowchart LR
  check_out["check_out<br/>CheckOut"]
  edit_cart["edit_cart<br/>EditCart"]
  saved["saved<br/>SaveForLater"]
  undo["undo<br/>UndoRemoval"]
  wishlist["wishlist<br/>KeepWishlist"]
  check_out -->|"pay_requested → request_checkout"| edit_cart
  edit_cart -->|"checkout_requested → pay"| check_out
  edit_cart -->|"checkout_started → start"| check_out
  edit_cart -->|"line → toggle"| wishlist
  edit_cart -->|"removed → capture"| undo
  edit_cart -->|"saved → stash"| saved
  edit_cart -.->|"saved"| page_flash["page: flash"]
  edit_cart -.->|"summary"| page_show["page: show"]
  edit_cart -->|"summary → summary"| check_out
  page -->|"mounted → mounted"| edit_cart
  page -->|"mounted → mounted"| check_out
  saved -.->|"count"| page_show["page: show"]
  saved -->|"moved → receive"| edit_cart
  saved -.->|"moved"| page_flash["page: flash"]
  ui -.->|"tab"| page_show["page: show"]
  undo -->|"expired → confirm_removal"| edit_cart
  undo -->|"restored → receive"| edit_cart
  undo -.->|"restored"| page_flash["page: flash"]
  wishlist -->|"added_to_cart → receive"| edit_cart
  wishlist -.->|"count"| page_show["page: show"]
  wishlist -->|"ids → wishlist_ids"| edit_cart
```

The checkout story inside:

```mermaid
flowchart LR
  %% check_out
  checkout["checkout<br/>Checkout"]
  checkout -.->|"address"| view_show["view: show"]
  checkout -.->|"blocked"| view_flash_for["view: flash_for"]
  checkout -.->|"done"| view_call_PlaceOrder["call PlaceOrder"]
  checkout -.->|"done"| view_redirect["view: redirect"]
  checkout -.->|"form"| view_form["view: form"]
  checkout -.->|"ready_to_pay"| view_task_StartPayment["task StartPayment → succeeded / failed"]
  checkout -.->|"step"| view_show["view: show"]
  checkout -.->|"step"| view_patch["view: patch"]
  in_failed((failed)) -->|"failed → failed"| checkout
  in_goto((goto)) -->|"goto → goto"| checkout
  in_mounted((mounted)) -->|"mounted → show_form"| checkout
  in_pay((pay)) -->|"pay → pay"| checkout
  in_start((start)) -->|"start → start"| checkout
  in_succeeded((succeeded)) -->|"succeeded → succeeded"| checkout
  in_summary((summary)) -.->|"summary"| view_show["view: show"]
```

## Run it

```bash
cd v47-typed-story-maps
mix deps.get
mix test
```
