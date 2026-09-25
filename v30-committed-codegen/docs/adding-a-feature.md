# Adding a feature to V30

> New to the design? [`techniques.md`](techniques.md) gives a one-recipe example of each mechanism
> this walkthrough combines (feature siblings, intent, render_data port, typed fact + reaction,
> effects, reaction placement, tooling). This file is the assembly; that file is the parts.

Two shapes of change. The feature *file* is identical to V29.1; what changes is that the manifest
is now a plain data module you edit, followed by one regeneration command.

## A. A new *rule* on the cart (belongs in the aggregate)

Unchanged from V28: add a single-function domain abstraction under `lib/zero_coupled/domain/`,
compose it in `Cart.recalc/1` (plus a struct field), test in `cart_test.exs`. If templates show it,
add the field to `CartItems.render_data/1` — templates read `@cart`, so no markup hunting. No
regeneration needed (the aggregate is not part of the manifest).

## B. A new *independent feature* — worked example: "recently viewed"

### 1. One feature file — `lib/zero_coupled/features/recently_viewed.ex`

Identical shape to V29.1: the pure module + `Intents` (with `use ZeroCoupled.Feature.Intents,
slot: :recent`) + `Components`, and a `Facts` sibling if it emits facts.

```elixir
defmodule ZeroCoupled.Features.RecentlyViewed do
  defstruct products: []
  def init(_opts), do: %__MODULE__{}

  def record(%__MODULE__{} = rv, product) do
    %{rv | products: [product | Enum.reject(rv.products, &(&1.id == product.id))] |> Enum.take(5)}
  end
end

defmodule ZeroCoupled.Features.RecentlyViewed.Intents do
  use ZeroCoupled.Feature.Intents, slot: :recent
  alias ZeroCoupled.{Effects, Features.RecentlyViewed}

  # A reaction: track products whose cart items get removed (wired in the manifest).
  def track_removed(%RecentlyViewed{} = rv, %{item: item}) do
    {RecentlyViewed.record(rv, item.product),
     [Effects.stream_insert(:recent_products, item.product, 0)]}
  end

  # An owned browser event (optional):
  intent :clear_recent
  def clear_recent(session, _args),
    do: {put_slot(session, %RecentlyViewed{}), [Effects.stream_reset(:recent_products, [])]}
end

defmodule ZeroCoupled.Features.RecentlyViewed.Components do
  use Phoenix.Component
  attr :id, :string, required: true
  attr :product, :map, required: true

  def recent_row(assigns) do
    ~H"""
    <div id={@id} class="text-sm text-zinc-500"><%= @product.name %></div>
    """
  end
end
```

The `handle_event("clear_recent", …)` clause (with param casting) will be **generated** — nothing
to add by hand in the page for it.

### 2. Manifest edits — `lib/zero_coupled_web/pages/cart_page/manifest.ex`

Edit the plain data functions (add the alias, the feature entry, and the reactor):

```elixir
def features do
  [ …, recent: RecentlyViewed]                                 # + alias RecentlyViewed
end

def reactions do
  [
    {CartFacts.ItemRemoved, to: [
       {:undo, Undo.Intents, :capture_removed},
       {:recent, RecentlyViewed.Intents, :track_removed}       # appended reactor
     ]},
    # …
  ]
end
```

If your reaction's port vocabulary differs from the emitter's field names, translate on the wire:
`{:recent, RecentlyViewed.Intents, :track_removed, transform: &%{product: &1.item.product}}`.

**If your feature emits facts of its own**, add a `Facts` sibling module with one struct per fact
(`@enforce_keys` on all fields) and emit those structs — construction typos and manifest wire typos
then fail at compile time.

### 3. Regenerate the glue

```bash
mix zc.gen                 # rewrites pages/cart_page/generated.ex from the manifest
```

Read the diff — that is the code you shipped. Commit **both** `manifest.ex` and `generated.ex`.
(`mix zc.gen --check` in the `test` alias will fail CI if you forget.)

### 4. Render — one call site in the ActionView

```heex
<RecentlyViewed.Components.recent_row :for={{id, p} <- @streams.recent_products} id={id} product={p} />
```

(and a `stream(:recent_products, [])` in `mount` if it renders a stream).

### 5. Tests

- Pure feature test: `test/zero_coupled/features/recently_viewed_test.exs`.
- One composed case in `cart_page_test.exs`: run `:remove_item` via `CartPage.run_intent/3` and
  assert the recent slot updated — this tests the *actual manifest wiring*, still no Phoenix/DB.
- `PageCheck.verify(CartPage)` already guards the new references.

### Deleting a feature

Delete the file; the manifest's `features`/`reactions`/alias entries fail compilation until removed;
`mix zc.gen` then shrinks `generated.ex`; the ActionView call site fails render compilation.
Nothing silent.

## Rules of thumb

| Kind of code | Goes in | Never |
|---|---|---|
| Domain abstraction | `domain/` (single function, pure) | reference anything above |
| Cart rule | `cart.ex` via `recalc` | live in a feature that shadows cart state |
| Feature state + intents + reactions + markup | its one feature file | reference another feature; write a foreign slot; emit facts from a reaction |
| Composition (fact wiring, event ownership, views) | `manifest.ex` (plain data) | hide in a runtime table or engine |
| Effect interpretation | `EffectInterpreter` (+ the page's `effect_opts/0`) | inside features |

**The workflow rule: change `manifest.ex` first, then `mix zc.gen`, then read the `generated.ex`
diff and commit both.**
