# Adding a feature to V35

A worked, **end-to-end** walkthrough — building the "recently viewed" feature the V35 way, so
the result passes the whole checked build (`zc.gen --check`, `zc.gen.contracts --check`,
`credo --only Purity`, tests). Every snippet below was compiled and run green before being written
here; see "Verified" at the end.

> New to the design? Read [`techniques.md`](techniques.md) first — it gives a one-recipe example
> of each mechanism this walkthrough combines (projection, contracts, the manifest channels,
> reaction placement). This file is the assembly; that file is the parts.

The V35 discipline in one line: **features are pure and zero-coupled; the manifest wires them; the
presentation reads projected ports and named contracts, never the domain.** Adding a feature means
touching a feature file, the manifest, and a call site — the checkers hold you to the rest.

"Recently viewed" = the last five products removed from the cart, shown in their own list, with a
Clear button. It only *reacts* (to cart removals) and owns one browser event (clear).

## 1. One feature file — `lib/zero_coupled/features/recently_viewed.ex`

Four sibling modules, the standard shape. The pure module owns state **and its projection ports**
(`render_data/1` for the summary, `row/1` for a stream row — neither ever leaks a domain struct).
The `Intents` module owns the browser event and the reaction. The `Components` module is a thin
composition over the `Catalog`, reading only the projected row.

```elixir
defmodule ZeroCoupled.Features.RecentlyViewed do
  @moduledoc "Products recently removed from the cart — a zero-coupled peer."
  defstruct products: []

  def init(_opts), do: %__MODULE__{}

  def record(%__MODULE__{} = rv, product),
    do: %{rv | products: [product | Enum.reject(rv.products, &(&1.id == product.id))] |> Enum.take(5)}

  # L5 presentation port (`render: :render_data` → `@recent`).
  def render_data(%__MODULE__{products: p}), do: %{count: length(p)}

  # Row port: the *projected* value the stream carries (never a domain struct).
  def row(product),
    do: %{id: product.id, product: %{thumbnail: product.thumbnail, name: product.name, amount: product.amount}}
end

defmodule ZeroCoupled.Features.RecentlyViewed.Intents do
  use ZeroCoupled.Feature.Intents, slot: :recent
  alias ZeroCoupled.Effects
  alias ZeroCoupled.Features.RecentlyViewed
  alias ZeroCoupled.Web.Contracts

  # Owned browser event — its handle_event clause is generated from this metadata.
  intent :clear_recent
  def clear_recent(session, _args),
    do: {put_slot(session, %RecentlyViewed{}), [Effects.stream_reset(Contracts.stream_name(:recent), [])]}

  # Reaction (slot, payload) → {slot, effects}: wired to :item_removed in the manifest.
  def track_removed(%RecentlyViewed{} = rv, %{item: item}) do
    {RecentlyViewed.record(rv, item.product),
     [Effects.stream_insert(Contracts.stream_name(:recent), RecentlyViewed.row(item.product), 0)]}
  end
end

defmodule ZeroCoupled.Features.RecentlyViewed.Components do
  use Phoenix.Component
  import ZeroCoupled.Catalog.ProductLineRow

  attr :id, :string, required: true
  attr :row, :map, required: true, doc: "projected: %{id, product}"

  def recent_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr" />
    """
  end
end
```

Note the three V35 things that keep it checker-clean and that a v30-era feature would get wrong:

- **the stream name is `Contracts.stream_name(:recent)`, never a literal `:recent_products`** —
  else `ContractPurity`'s `contract_literal` rule fails the build;
- **the component takes a projected `row`, not a domain struct**, and composes
  `Catalog.ProductLineRow` — else `ComponentPurity` flags the domain-shape reach;
- **the reaction returns `{slot, effects}`** (single level, no fact) — which is what lets it live
  in the manifest (see §3 and the reaction-placement note).

## 2. Name the contract — `lib/zero_coupled/web/contracts.ex`

The Clear button fires an event and the feature owns a stream; both names are single-sourced.
Add one line to each map (append-only):

```elixir
@events %{ …, clear_recent: "clear_recent", … }
@streams %{ …, recent: :recent_products, … }
```

## 3. Wire it in the manifest — `lib/zero_coupled_web/pages/cart_page/manifest.ex`

Three plain-data edits — the diagram, changed first:

```elixir
alias ZeroCoupled.Features.{CartItems, Undo, SavedItems, Wishlist, RecentlyViewed, CheckoutFlow, PageUI}

def features do
  [ …,
    recent: {RecentlyViewed, render: :render_data},   # new slot + its presentation port
    … ]
end

def reactions do
  [
    {CartFacts.ItemRemoved,
     to: [
       {:undo, Undo.Intents, :capture_removed},
       {:recent, RecentlyViewed.Intents, :track_removed}   # appended reactor — this is the whole wire
     ]},
    …
  ]
end
```

A removal already emits `%CartFacts.ItemRemoved{item, item_id}`; the manifest projects it
(`Map.from_struct/1`) to `%{item: …, item_id: …}` and hands the reaction its `%{item: item}`. No
feature learned anything about another; the wire is one appended line.

## 4. Regenerate the glue

```
mix zc.gen           # rewrites the committed generated.ex (new slot in Session, new apply_fact clause,
                     # generated handle_event("clear_recent", …))
mix zc.gen.contracts # rewrites assets/js/contracts.js from the new contract names
```

Both are committed and reviewed like any source; `--check` (wired into `mix test`) fails the build
if you forget.

## 5. Render — one call site in the ActionView

`lib/zero_coupled_web/live/cart_live/index_view.ex`, reading **only ports**: the `@recent` render
port, the projected stream rows, and `Contracts` for the event + dom-id:

```elixir
alias ZeroCoupled.Features.RecentlyViewed.Components, as: RecentRows

# …in render/1:
<div :if={@recent.count > 0} class="py-4 border-t mt-6">
  <div class="flex items-center justify-between mb-2">
    <h3 class="text-sm font-semibold text-zinc-700">Recently viewed</h3>
    <button phx-click={Contracts.event(:clear_recent)} class="text-xs text-zinc-400">Clear</button>
  </div>
  <div id={Contracts.stream_dom_id(:recent)} phx-update="stream">
    <RecentRows.recent_row :for={{dom_id, row} <- @streams.recent_products} id={dom_id} row={row} />
  </div>
</div>
```

And initialize the stream at mount (`cart_page.ex`), alongside the others:

```elixir
|> stream(Contracts.stream_name(:recent), [])
```

## 6. Tests

- **Pure/composed** (no Phoenix, no DB): `RecentlyViewed` functions directly, and the reaction via
  `CartPage.run_pure(session, &Generated.apply_fact(&1, %CartFacts.ItemRemoved{…}))` — assert the
  product is recorded and a `%StreamInsert{name: :recent_products}` effect is produced.
- **Integration**: click remove, assert the name shows in the Recently-viewed section; click Clear,
  assert it empties.
- **Watch for interactions.** Adding this feature legitimately changed one existing assertion: a
  cart test refuted the removed product's *name* appeared anywhere after removal — but recently-viewed
  now echoes it. The honest fix scopes the assertion to the cart stream
  (`refute html =~ ~s(id="cart_items-#{id}")`). A new feature changing a sibling's rendered output is
  a real thing; the test suite catching it is the system working.

## Deleting a feature

Delete `features/recently_viewed.ex`, remove its `feature` line and its `to:` reactor from the
manifest, its two `Contracts` entries, and its ActionView call site + mount stream; `mix zc.gen`.
Two of those edits fail the build loudly if forgotten — deletion is nearly as guided as addition.

## Rules of thumb (what the checkers enforce, so you don't have to remember)

- A feature reads/writes **only its own slot**; it never reads `session.<peer>` (the composition
  resolves cross-slot data and passes it in — see `techniques.md` §"Cross-slot inputs").
- Cross-feature effects go out as **typed facts** wired in the manifest, never a direct peer call.
- **No literal event/stream/hook names** in markup or emitters — always `Web.Contracts`.
- Presentation reads **projected ports**, never a domain struct or a deep `@a.b.c` reach.
- A **reaction that emits a fact** can't be a manifest wire (it would cascade); it goes in a shell
  clause. `elixir run_reaction_audit.exs` checks placement.

## Verified

The exact feature above was added to V35, run through `mix zc.gen`, `mix zc.gen.contracts`,
`mix credo --only Purity` (0 findings), `elixir run_reaction_audit.exs` (0 findings — `track_removed`
is a correctly-placed manifest reaction), and `mix test` (**162 tests, 0 failures**), then removed
to keep the variant's measured surface stable. The walkthrough is the real diff.
