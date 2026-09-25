# V30 techniques — one recipe per mechanism

The parts a builder needs to work in V30, each with a minimal worked example from the real code.
The assembly into a feature is [`adding-a-feature.md`](adding-a-feature.md); the layer map is
[`architecture.md`](architecture.md). Every mechanism here is either generated or a plain data
declaration, so the recipe is "what to write" and `mix zc.gen --check` + the tests catch mistakes.

The layers, top (concrete) to bottom (abstract) — dependencies point **down** only:

```
Manifest (the diagram: features · reactions · action_views)   ← change this first
Generated glue (committed; mix zc.gen)  ·  the page shell (irregular edges + run/2)
Features: pure module + Facts + Intents + Components          ← app-specific, one deletable unit
Cart aggregate · domain abstractions (single-function)        ← reusable
Effects · EffectInterpreter · PageGenerator                   ← platform
```

> **Scope note.** V30 is the committed-codegen core. It deliberately does *not* include the
> presentation-purity checkers, `Web.Contracts`, `Catalog.*`, the `flows` channel, or the `config:`
> channel — those are later variants (V32–V35). So in V30 you write **literal** stream/event names
> and keep calibration in the domain modules; that is correct *for V30*. Where a technique has a
> known limitation the later variants close, this doc says so inline, so you can decide whether V30
> is enough for your app or you want the V33/V35 additions.

---

## 1. A feature — the four siblings

One file, up to four modules. The **pure module** owns state and (optionally) an `render_data/1`
presentation port. **`Facts`** are the typed events it emits. **`Intents`** are the browser events
it owns plus the reactions it offers. **`Components`** is its markup.

```elixir
defmodule ZeroCoupled.Features.Wishlist do        # pure: no Phoenix, no peers
  defstruct products: []
  def init(_opts), do: %__MODULE__{}
  def member?(%__MODULE__{products: ps}, id), do: Enum.any?(ps, &(&1.id == id))
  def toggle(%__MODULE__{} = wl, product), do: # … {wl, :added | :removed}
end
```

Rule: the pure module depends only *downward* (domain, `Money`), never on a peer feature. What a
peer must do in response is emitted as a **fact** (§4), never a direct call.

## 2. An intent (an owned browser event)

`(session, args) -> {session, effects}` or `{session, effects, facts}`. Declared with `intent`
metadata so its `handle_event` clause (with param casts) is **generated** — you don't hand-write
dispatch. Writes only its own slot via `put_slot/2`; may *read* other slots (see the limitation).

```elixir
defmodule ZeroCoupled.Features.CartItems.Intents do
  use ZeroCoupled.Feature.Intents, slot: :cart
  alias ZeroCoupled.{Cart, Effects}
  alias ZeroCoupled.Features.CartItems.Facts

  intent :remove_item, params: [item_id: :int]        # → generates handle_event("remove_item", …)
  def remove_item(session, %{item_id: id}) do
    case Cart.remove_item(session.cart, id) do
      {:ok, cart, removed} ->
        {put_slot(session, cart),
         [Effects.stream_delete(:cart_items, removed), Effects.push("item-removed", %{id: removed.id})],
         [%Facts.ItemRemoved{item: removed, item_id: id}]}       # ← a fact (3-tuple return)
      :error -> {session, []}
    end
  end
end
```

`params:` types are `:int | :string | :atom`. Effects are inert **data** (§5), interpreted at the
edge — that keeps the intent pure and unit-testable with no socket.

> *V30 limitation (R2):* `remove_item` reads `session.cart`, which is its **own** slot — fine. But
> some intents read a *peer* slot (`CheckoutFlow` reads `session.cart`); V30 allows this by
> convention. V35 resolves such reads in the composition instead. Fine at V30's scale.

## 3. The `render_data` presentation port + per-slot assigns

A feature can expose a summary map for templates, decoupling the view from aggregate field names.
Mark the slot `render: :render_data` in the manifest; it is assigned as `@cart`.

```elixir
def render_data(%Cart{} = cart) do
  %{item_count: cart.item_count, subtotal: cart.subtotal, total: cart.total, empty?: Cart.empty?(cart), …}
end
```

The generated `put_session` also assigns **each slot individually** (`@cart_slot`, `@undo_slot`, …).
Because Elixir updates are structurally shared, an untouched slot is the *same term*, so `assign/3`
no-ops and LiveView skips that feature's template regions — near per-feature change tracking with
plain function components. And the `@cart` render_data map is **gated**: recomputed only when the
cart slot's term actually changed (an O(1) `:erts_debug.same/2` check), so an event touching another
feature does zero cart-presentation work.

> *V30 limitation:* the row `Components` still read the domain struct directly
> (`@item.product.name`) and reference domain modules in the ActionView. V32 adds boundary
> *projection* + a checker so the presentation reads only neutral port values. In V30 this is
> allowed.

## 4. A typed fact + a manifest reaction (cross-feature, zero-coupled)

A feature emits a **struct it owns** (compile-checked keys); the manifest routes it to another
feature's reaction. Neither feature names the other.

```elixir
# emitter — CartItems.Facts:
defmodule ItemRemoved, do: (@enforce_keys [:item, :item_id]; defstruct [:item, :item_id])

# reactor — a slot-scoped function (never sees the session):
def capture_removed(%Undo{} = undo, %{item: item, item_id: id}), do: {Undo.capture(undo, item), [effects…]}

# the wire — manifest reactions/0:
{CartFacts.ItemRemoved, to: {:undo, Undo.Intents, :capture_removed}}
```

**Transform** — when the emitter's vocabulary ≠ the reactor's port, translate *in the manifest* (the
meaning lives in the wiring), never by bending either feature. The generator splices the capture's
source into the generated clause:

```elixir
{SavedFacts.MovedToCart, to: {:cart, CartItems.Intents, :receive_item, transform: &%{item: &1.saved_item}}}
```

Reactions are **single level**: `(slot, payload) -> {slot, effects}`. A reaction that must itself
emit a fact can't be a manifest wire (it would cascade) — it goes in a shell clause (§6).

## 5. The effect vocabulary (side effects as data)

The one "paradigm" the pure layers speak. Every effect is a struct (typos are compile errors); the
`EffectInterpreter` turns them into Phoenix calls at the edge. Constructors:

```elixir
Effects.flash(:info, "Saved")            Effects.push("item-removed", %{id: id})
Effects.stream_insert(:cart_items, item) Effects.stream_delete(:cart_items, item)
Effects.patch("/cart/checkout")          Effects.navigate("/x")   Effects.redirect_external(url)
Effects.start_timer(:undo, 5_000, msg)   Effects.cancel_timer(:undo)
Effects.persist_quantity(cart_id, id, q) Effects.persist_remove(cart_id, id)
Effects.start_checkout(line_items, meta)
```

Because effects are inert, tests assert on them directly:
`assert has?(effects, &match?(%Effects.StreamInsert{name: :cart_items}, &1))`.

> *V30 note (R5):* stream names (`:cart_items`), event strings (`"item-removed"`), and hook names
> live as literals in intents, markup, and `app.js`; PubSub uses tagged tuples
> (`{:stock_changed, …}`). This works but is unchecked duplication. V32's `Web.Contracts` +
> typed facts single-source and enforce them; reach for it when the app grows.

## 6. Irregular edges + reaction placement (manifest vs shell)

Most events are generated from `intent` metadata. Anything a manifest can't express is a
**hand-written clause in the page module** (`cart_page.ex`), ending in `run/2` (the one house
pattern). Two kinds:

- **I/O-then-intent** — fetch first, then run a pure intent:
  ```elixir
  def handle_event("pay", _params, socket) do
    stock = Products.stock_levels(…)           # I/O
    run(socket, &CheckoutFlow.Intents.pay(&1, stock))
  end
  ```
- **Reactions the manifest can't hold** — a reaction that emits a fact, an async result, or a
  non-fact message. The undo timer is the canonical case (its reactor emits `RemovalFinal`, so it
  can't be single-level):
  ```elixir
  def handle_info({:undo_expired, id}, socket), do: run(socket, &Undo.Intents.undo_expired(&1, id))
  ```

**Placement rule:** a reaction goes in `reactions/0` (declarative) if it's pure, single-level, and
fact-triggered; it goes in a shell clause (imperative) if it's forced (async, does I/O, non-fact
message, or emits a fact). Declare when numerous/regular; inline when rare/irregular — the same
amortization line everywhere. (V35 ships a `run_reaction_audit.exs` that checks this mechanically.)

## 7. The tooling

```
mix zc.gen                 # regenerate the committed generated.ex from the manifest
mix zc.gen --check         # fail the build if generated.ex drifted (wired into `mix test`)
mix zc.gen CartPage        # one page
mix zc.trace remove_item   # print the full story of an intent on one screen (owner, effects, wired reactions)
```

`ZeroCoupledWeb.PageCheck.verify(CartPage)` is a one-line manifest-integrity test (every feature
exports `init/1`, every fact is a struct, every reaction target/intent owner is exported, cast
types are known).

---

## The build is the spec

`mix test` runs `zc.gen --check` then the suite. Change the manifest, run `mix zc.gen`, commit the
regenerated file; a forgotten regen fails CI. Pure feature/composed-page tests need no DB and no
LiveView process (`CartPage.run_intent/3`, `run_pure/2`) — that fast, inspectable test surface is
the payoff of keeping the core effect-as-data pure.

Where to go further: V32 adds enforced presentation zero-coupling (`Web.Contracts`, `Catalog.*`,
checkers), V33 a `flows` channel for URL-driven wizards, V34 moves calibration onto the diagram, V35
resolves cross-slot inputs in the composition. Each is an additive step up the R1–R5 encoding rubric
(see `ala_lab/docs/ALA-encoding-applied-to-v30.md` for where V30 stands and why).
