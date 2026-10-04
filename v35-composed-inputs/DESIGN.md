# V35 design: manifest, committed codegen, facts and reactions

A Phoenix LiveView design where each page's composition is a **manifest**: a plain data module listing
the page's feature slots and their calibration, which typed fact goes to which reaction, the view for
each `live_action`, and its wizard flows. A generator (`mix zc.gen`) turns the manifest into a
**committed glue file**. That file holds the session struct, the `handle_event` clauses, the fact
routing and the flow tables. Features are pure. Each one owns:

- a state module;
- `Facts`, the typed events it emits;
- `Intents`, the browser events it handles and the reactions it offers;
- `Components`, its markup.

Intents return effects as data, and one interpreter applies them at the edge. The build enforces the
rules: drift checks on the generated files, plus Credo checks for core purity, component purity and
contract purity.

Use it when you want the most enforcement and are willing to run a generator and learn its
vocabulary. Later variants reach the same separation with much less machinery: V39-max with a
bindings map, V48 and V50 with plain clauses.

## At a glance

| | |
|---|---|
| Wiring form | `Manifest`: `features/0` (slots and `config:`), `reactions/0` (fact → slot reaction), `action_views/0`, `flows/0` |
| Generated | `Generated` and `Session` (about 570 lines for the cart page), committed and checked with `mix zc.gen --check` |
| Where feature state lives | one generated `%Session{}` struct in assigns, one field per slot |
| Features | a pure module, `Facts`, `Intents` (`use ZeroCoupled.Feature.Intents`), `Components` |
| Side effects | `ZeroCoupled.Effects` structs, applied by `EffectInterpreter` |
| Contracts | every event, stream, hook and push-event name in `Web.Contracts`; `assets/js/contracts.js` generated from it |
| Checks | `zc.gen --check`, `zc.gen.contracts --check`, `credo --only Purity`, a reaction-placement audit, a cross-slot-read detector |
| Message hops | none |

## Layers

From the most concrete at the top to the most abstract at the bottom:

| Layer | What lives there |
|---|---|
| The diagram | `ZeroCoupledWeb.*Page.Manifest`: slots, calibration, reactions, views, flows |
| Generated glue and shell | `*Page.Generated` and `*Page.Session` (generated), and the hand-written page (`CartPage`): mount, the irregular events, `run/2` |
| Features | `ZeroCoupled.Features.*`: each a pure module plus `Facts`, `Intents` and `Components` |
| Generic UI and contracts | `ZeroCoupled.Catalog.*` components, `ZeroCoupled.Web.Contracts`, the generated `ZeroCoupled.Flows` |
| Domain | `ZeroCoupled.Cart` aggregate, `ZeroCoupled.Domain.*` (calibration passed in as data) |
| Platform | `ZeroCoupled.Effects`, `ZeroCoupledWeb.EffectInterpreter`, `ZeroCoupled.Feature.Intents`, the generators, the Credo checks, `ZeroCoupled.Foundation.*` |

## Building block 1: a feature

A feature has a pure module (struct, functions, and a `render_data/1` projection for the view), plus
`Facts`, `Intents` and `Components` siblings in the same file:

```elixir
defmodule ZeroCoupled.Features.Undo do
  defstruct pending: nil, window_ms: nil
  def init(opts), do: %__MODULE__{window_ms: (opts[:config] || [])[:window_ms]}
  def capture(%__MODULE__{} = undo, item), do: %{undo | pending: %{item: item}}
  def take(%__MODULE__{pending: %{item: item}} = undo), do: {%{undo | pending: nil}, item}
  def render_data(%__MODULE__{} = undo), do: %{pending?: pending?(undo)}
end

defmodule ZeroCoupled.Features.Undo.Facts do
  defmodule ItemRestored do
    @enforce_keys [:item]
    defstruct [:item]
  end
end
```

The pure module depends only downward, on the domain and `Money`. When a peer needs to respond, the
feature emits a fact. It never calls the peer.

## Building block 2: intents

```elixir
defmodule ZeroCoupled.Features.Wishlist.Intents do
  use ZeroCoupled.Feature.Intents, slot: :wishlist

  intent :remove_wishlist, params: [product_id: :int]
  def remove_wishlist(session, %{product_id: id}) do
    {wl, product} = Wishlist.take(session.wishlist, id)
    {put_slot(session, wl), [Effects.stream_delete(Contracts.stream_name(:wishlist), Wishlist.row(product))]}
  end
end
```

- An intent is `(session, args) -> {session, effects}` or `{session, effects, facts}`.
- `intent name, params:` only records metadata. The generator reads it to write the `handle_event`
  clause with param casts.
- `put_slot/2` writes the feature's own slot. A feature may not read another slot. When it needs
  another slot's data, the page's shell resolves the data and passes it in.
- A reaction is slot-scoped, `(slot_state, payload) -> {slot_state, effects}`, and never sees the
  session.

## Building block 3: effects and contracts

```elixir
Effects.flash(:info, "Item restored")
Effects.stream_insert(Contracts.stream_name(:cart), CartItems.row(cart, item))
Effects.start_timer(:undo, ms, %Undo.Facts.UndoExpired{item_id: id})
Effects.patch_flow(:checkout, step)
Effects.persist_remove(cart_id, item_id)
Effects.finalize_order(cart_id)
```

`EffectInterpreter.apply_all/3` turns each effect into a socket change or store call.
`Web.Contracts` holds every event and stream name, and markup reads names from it
(`on={Contracts.event(:remove_item)}`), never as literals. Rows are projected in the intent through
the feature's `row/…` function, so components never touch domain structs.

## Wiring: the manifest

```elixir
@retail_pricing [
  shipping: %{standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000}, ...},
  promo: %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50},
  gift_wrap_unit: 299
]

def features do
  [
    cart: {CartItems, render: :render_data, config: [pricing: @retail_pricing]},
    undo: {Undo, render: :render_data, config: [window_ms: 5_000]},
    saved: {SavedItems, render: :render_data},
    wishlist: {Wishlist, render: :render_data},
    checkout: CheckoutFlow,
    ui: PageUI
  ]
end

def reactions do
  [
    {CartFacts.ItemRemoved, to: {:undo, Undo.Intents, :capture_removed}},
    {UndoFacts.ItemRestored, to: {:cart, CartItems.Intents, :receive_item}},
    {SavedFacts.MovedToCart, to: {:cart, CartItems.Intents, :receive_item, transform: &%{item: &1.saved_item}}},
    {BroadcastFacts.StockChanged, to: {:cart, CartItems.Intents, :set_stock}}
  ]
end

def action_views, do: [index: IndexView, checkout: CheckoutView]

def flows do
  [checkout: [initial: :address, milestones: [...], transitions: [{:address, :submit_address, :payment}, ...],
              paths: [address: "/cart/checkout", payment: "/cart/checkout/payment"]]]
end
```

`config:` is spliced into each slot's `init/1` when the code is generated. A `transform:` translates
one feature's payload into the shape another feature's reaction expects. A fact can fan out to several
reactors. Reactions are single-level: a reactor that would itself emit a fact has to be a shell clause.

## The generated glue and the shell

`Generated` holds:

- `Session.new/1`, which builds each slot with its config;
- `run_pure/2`;
- `page_event/4`, one clause per declared intent, with param casts;
- `apply_fact/2`, one clause per reaction;
- `declared_facts/0`;
- the flow helpers (`flow_param_step/2`, `flow_path/2`);
- `page_render/1`, which picks the action view.

The hand-written page holds only what the manifest can't express:

```elixir
def handle_event("toggle_wishlist", %{"item-id" => id}, socket) do
  item = Enum.find(socket.assigns.session.cart.items, &(&1.id == String.to_integer(id)))
  run(socket, &Wishlist.Intents.toggle_wishlist(&1, item))
end

def handle_event(event, params, socket), do: Generated.page_event(event, params, socket, &run/2)

def handle_info(%Undo.Facts.UndoExpired{item_id: item_id}, socket),
  do: run(socket, &Undo.Intents.undo_expired(&1, item_id))

def handle_info(%mod{} = fact, socket) do
  if mod in Generated.declared_facts(), do: run(socket, &Generated.apply_fact(&1, fact)), else: {:noreply, socket}
end

defp run(socket, fun) do
  {session, effects} = Generated.run_pure(socket.assigns.session, fun)
  {:noreply, socket |> Generated.put_session(session) |> EffectInterpreter.apply_all(effects, effect_opts())}
end
```

The shell also handles events that need I/O first (`pay` reads fresh stock, `add_wishlisted_to_cart`
stores a line), the address changeset form, and `handle_async` for the payment, which emits
`Effects.finalize_order` and runs the success intent.

## Checks

The `test` alias runs these before the tests:

- `mix zc.gen --check` fails if `Generated` differs from what the manifest would generate;
- `mix zc.gen.contracts --check` fails if `contracts.js` differs from `Web.Contracts`;
- `credo --only Purity` runs three checks: `CorePurity` (the core never references the web layer),
  `ComponentPurity` (components never reference domain or feature modules), and `ContractPurity` (no
  restated event or stream literals).

Two scripts run by hand. A reaction audit checks that each reaction sits on the right side (manifest
or shell). A `CrossSlotRead` detector reports intents that read another slot.

## Applying it to another project

1. Copy the platform: `Effects`, `EffectInterpreter`, `Feature.Intents`, the generators
   (`PageGenerator`, `FlowsGenerator`, `ManifestResolver`), the mix tasks, and the Credo checks.
2. Write each feature as one file with four modules: pure state with `init/1`, `render_data/1` and
   `row/…`; `Facts`; `Intents` with `intent` declarations; and `Components` built from generic catalog
   components.
3. Put every event and stream name in a `Contracts` module.
4. Write each page's manifest (slots with `config:`, reactions, action views, flows), run `mix zc.gen`,
   and commit the generated file.
5. Write the page shell: mount through `Generated.mount_session`, the irregular events, `run/2`, and
   the generic fact `handle_info`.
6. Add the checks to your `test` alias.

V35's own `docs/adding-a-feature.md` walks through adding a feature end to end.

## Trade-offs and limits

- A lot of machinery: generators and an audit of about 1,000 lines, three Credo checks, a macro, a manifest
  vocabulary, and committed generated files to review.
- Every change has an extra step: edit the manifest, then regenerate.
- Reactions are single-level, so some wiring sits in the manifest and some in the shell. The audit
  exists to keep that split right.
- Some cross-slot reads remain in the shell as one-off joins.
- Several literals stay in features on purpose: the low-stock threshold and the PO and postal-code
  regexes.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/pages/cart_page/manifest.ex` | the diagram |
| `lib/zero_coupled_web/pages/cart_page/generated.ex` | the committed glue |
| `lib/zero_coupled_web/pages/cart_page.ex` | the hand-written shell |
| `lib/zero_coupled/features/undo.ex` | a feature's four modules |
| `lib/zero_coupled/effects.ex`, `lib/zero_coupled_web/effect_interpreter.ex` | effects and their interpreter |
| `lib/zero_coupled/web/contracts.ex` | the contract names |
| `lib/zero_coupled/credo/` | the purity checks |
| `docs/techniques.md`, `docs/adding-a-feature.md`, `docs/architecture.md` | one recipe per mechanism, a walkthrough, the layer map |
