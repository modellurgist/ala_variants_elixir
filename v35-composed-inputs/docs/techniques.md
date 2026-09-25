# V35 techniques — one recipe per mechanism

The parts a builder needs, each with a minimal worked example drawn from the real code. The
assembly of these into a feature is [`adding-a-feature.md`](adding-a-feature.md); the layer map is
[`architecture.md`](architecture.md). Every mechanism here is enforced or generated, so the recipe
is "what to write"; the build tells you if you got it wrong.

The layers, top (concrete) to bottom (abstract) — dependencies point **down** only:

```
Manifest (the diagram: features · reactions · action_views · flows · config)   ← change first
Generated glue (committed; mix zc.gen)  ·  the page shell (irregular edges + run/2)
Features: pure module + Facts + Intents + Components         ← app-specific, one deletable unit
Catalog components · Web.Contracts · ZeroCoupled.Flows       ← generic, reused across features/pages
Cart aggregate · domain abstractions (parametric)            ← [commerce], reused across consumers
Effects · EffectInterpreter · PageGenerator                  ← [] platform
```

---

## 1. A zero-coupled feature (the four siblings)

One file, four modules. Pure module = state + **projection ports**. `Facts` = the typed events it
emits. `Intents` = browser events it owns + reactions it offers. `Components` = thin markup over
the catalog.

```elixir
defmodule ZeroCoupled.Features.Wishlist do          # pure: no Phoenix, no peers
  defstruct products: []
  def init(_opts), do: %__MODULE__{}
  def toggle(%__MODULE__{} = wl, product), do: # … {wl, :added | :removed}
  def render_data(%__MODULE__{} = wl), do: %{count: length(wl.products), product_ids: …}  # port → @wishlist
  def row(product), do: %{id: product.id, product: %{thumbnail: …, name: …, amount: …}}   # projected row
end
```

Rule: the pure module depends only *downward* (domain/`Money`), never on another feature. What a
peer must do in response is emitted as a **fact** (§4), never called directly.

## 2. An intent (an owned browser event)

`(session, args) -> {session, effects}` or `{session, effects, facts}`. Declared with `intent`
metadata so the `handle_event` clause (with param casts) is **generated** — you never hand-write
dispatch. Writes only its own slot via `put_slot/2`.

```elixir
defmodule ZeroCoupled.Features.Wishlist.Intents do
  use ZeroCoupled.Feature.Intents, slot: :wishlist
  alias ZeroCoupled.{Effects, Web.Contracts}

  intent :remove_wishlist, params: [product_id: :int]     # → generates handle_event("remove_wishlist", …)
  def remove_wishlist(session, %{product_id: id}) do
    {wl, product} = ZeroCoupled.Features.Wishlist.take(session.wishlist, id)
    {put_slot(session, wl), [Effects.stream_delete(Contracts.stream_name(:wishlist), Wishlist.row(product))]}
  end
end
```

`params:` types are `:int | :string | :atom`. Effects are **data** (`Effects.*`), interpreted at
the edge — that is what keeps the intent pure and testable without a socket.

## 3. Boundary projection (the presentation never sees the domain)

A stream carries a **projected row map**, produced by the feature's `row/…` port *in the intent*
(server-side, where touching the domain is legitimate). The component reads only that shape.

```elixir
# in the intent (domain access OK here):
Effects.stream_insert(Contracts.stream_name(:cart), CartItems.row(cart, item))

# the component — no domain module, no @a.b.c reach, passes ComponentPurity:
def cart_item_row(assigns) do
  ~H|<.product_line id={@id} product={@row.product} cols="4rem_1fr_auto_auto">…</.product_line>|
end
```

Why in the intent, not the markup: every event that changes a row already re-inserts it, so the
projection can't go stale; and it keeps the whole domain out of the presentation layer, which is
what `ComponentPurity` enforces. A cross-feature flag a row needs (e.g. `wishlisted`) is passed at
the call site from *its* port, not baked into the row.

## 4. A typed fact + a manifest reaction (cross-feature, zero-coupled)

A feature emits a **struct** it owns (compile-checked keys); the manifest routes it to another
feature's reaction. Neither feature names the other.

```elixir
# emitter — CartItems.Facts:
defmodule ItemRemoved, do: (@enforce_keys [:item, :item_id]; defstruct [:item, :item_id])
# emitted from an intent's 3-tuple return:
{put_slot(session, cart), [effects…], [%Facts.ItemRemoved{item: removed, item_id: id}]}

# reactor — a slot-scoped function (never sees the session):
def capture_removed(%Undo{} = undo, %{item: item, item_id: id}), do: {Undo.capture(undo, item), [effects…]}

# the wire — manifest reactions/0:
{CartFacts.ItemRemoved, to: {:undo, Undo.Intents, :capture_removed}}
```

**Transform** — when the emitter's vocabulary ≠ the reactor's port, translate *in the manifest*
(the meaning lives in the wiring, §3.8), never by bending either feature:

```elixir
{SavedFacts.MovedToCart, to: {:cart, CartItems.Intents, :receive_item, transform: &%{item: &1.saved_item}}}
```

**Fan-out** — one fact, several reactors: `to: [ {:a, …}, {:b, …} ]`.

Reactions are **single level**: `(slot, payload) -> {slot, effects}`. A reaction that itself needs
to emit a fact can't be a manifest wire (see §7).

## 5. A cross-boundary contract (`Web.Contracts`)

Every event/stream/hook/push-event name lives once, here. Markup and emitters reference the
function; the JS half is generated. `ContractPurity` fails the build on any restated literal.

```elixir
@events %{ remove_item: "remove_item", … }
def event(name), do: Map.fetch!(@events, name)
@streams %{ cart: :cart_items, … }
def stream_name(slot), …; def stream_dom_id(slot), …   # one slot→name→dom-id relationship
```

```elixir
# markup: an interpolated port, never phx-click="remove_item"
<.action_button on={Contracts.event(:remove_item)} phx-value-item-id={@row.id} label="Remove" />
```

`mix zc.gen.contracts` writes `assets/js/contracts.js` from these maps; `--check` guards drift; JS
imports the names (`Hooks[HookNames.remove_fade]`, `Streams.cart`) instead of hardcoding them.

## 6. The `config:` channel (calibration on the diagram — V34)

Domain abstractions stay **generic** (take calibration as data); the values that make the app
*this* app live in the manifest and are spliced into `init/1` by the generator.

```elixir
# generic abstraction — no baked rates:
def call(method, subtotal, rates), do: # …

# the diagram carries the box-contents:
@retail_pricing [shipping: %{standard: %{label: "Standard", cost: 599, free_above: 5000}, …}, promo: %{…}]
def features, do: [ cart: {CartItems, render: :render_data, config: [pricing: @retail_pricing]}, … ]

# the feature threads it in:
def init(opts), do: Cart.new(cart_id: opts[:cart_id], items: …, config: (opts[:config] || [])[:pricing])
```

Measured cost: ~+1.8% author bits, and it makes per-consumer divergence ~0.39× the cost of forking
a shared abstraction (the portal configures the same `Cart`/`VolumeTier`/`CalculateShipping` with
different numbers). Hoist *shared/tunable* literals; leave essential per-feature content (a
validation regex) in the feature.

## 7. A flow (a URL-driven wizard skeleton — V33)

Steps, transitions, milestones, and per-step URLs are declared in the manifest's `flows/0`; the
generator emits the transition table into the **core** `ZeroCoupled.Flows` (features consult it)
and the URL/milestone glue into the **page**.

```elixir
def flows do
  [checkout: [
    initial: :address,
    milestones: [address: "Address", payment: "Payment"],
    transitions: [{:address, :submit_address, :payment}, {:payment, :edit_address, :address},
                  {:payment, :pay, :processing}, {:error, :pay, :processing}],
    paths: [address: "/cart/checkout", payment: "/cart/checkout/payment"]]]
end
```

```elixir
# the feature advances off the table (no hardcoded next-step), URL emitted as an effect:
def submit_address(%__MODULE__{} = c, params), do: # … goto(c, ZeroCoupled.Flows.advance(:checkout, c.step, :submit_address))
{put_slot(session, c), [Effects.patch_flow(:checkout, c.step)]}   # interpreter resolves the URL — core has no path literal
```

`handle_params` maps URL→step and routes it through a feature-gated `goto_step` (browser back works;
forward jumps that skip validation are ignored — `can_goto?/2` is feature policy). **Result-fact**
edges (async payment settled → complete/error) stay in `reactions`/intents, not `flows` — each
channel carries the edge type it's shaped for.

## 8. Reaction placement — manifest vs shell (and the audit)

Two ways to wire a reaction; the choice is mechanical:

- **Manifest `reactions/0`** — declarative, amortized. Use when the reactor is **pure, single-level,
  fact-triggered** (returns `{slot, effects}`). This is the default; a table pays when reactions are
  numerous.
- **A shell clause** (`handle_info`/`handle_async` calling an intent via `run/2`) — imperative,
  marginal. *Forced* when: it's an async result, it does I/O, it's a non-fact message, or **the
  reactor emits a fact** (a cascade, illegal in a single-level manifest reaction). Example: the undo
  timer's `undo_expired` emits `RemovalFinal`, so it must be a shell clause.

This is the same amortization spectrum as everything else: declare when numerous/regular, inline
when rare/irregular. Don't build a manifest channel for one wire; don't hand-wire a pure reaction
that belongs in the table. `elixir run_reaction_audit.exs` checks every reaction is on the correct
side (0 findings on V35).

## 9. Cross-slot inputs (the R2 rule — V35)

A feature reads/writes **only its own slot**. When an intent needs data from another slot, the
**composition** (shell) resolves it and passes it in — the feature never reads `session.<peer>`.

```elixir
# feature: takes the resolved value, knows no peer slot
def toggle_wishlist(session, nil), do: {session, []}
def toggle_wishlist(session, item), do: # … uses item.product

# shell: the composition owns the cross-slot join
def handle_event("toggle_wishlist", %{"item-id" => id}, socket) do
  item = Enum.find(socket.assigns.session.cart.items, &(&1.id == String.to_integer(id)))
  run(socket, &Wishlist.Intents.toggle_wishlist(&1, item))
end
```

This is the input-side mirror of reactions (which wire outputs). Its heavy form would be a manifest
`selectors:` channel; the light form here (shell resolution) is right until cross-slot reads
proliferate. Note that a feature calling `Cart.empty?(cart)` on a value passed in is *fine* — that's
a downward dependency on the shared aggregate, not a peer read. A `CrossSlotRead` detector
(`run_cross_slot_read.exs`) reports raw `session.<peer>` reads in intents.

---

## The build is the spec

`mix test` runs the whole seam: `zc.gen --check` (glue matches the manifest), `zc.gen.contracts
--check` (JS matches Contracts), `credo --only Purity` (Core/Component/Contract purity), then the
tests. If a technique above is done wrong — a literal in markup, a domain reach in a component, a
stale regen, a peer-slot read — the build fails with the specific rule. You don't have to hold the
rules in your head; you have to run the build.

Deeper rationale and measurements for each mechanism: the `Q-*` and `v3x-*` docs in
`ala_lab/docs/` (the checker baseline, the D6 reuse result, the R3/R2 spikes, the reaction-placement
audit).
