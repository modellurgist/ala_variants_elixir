# V30 design: committed codegen

A Phoenix LiveView design where each page's composition is a **manifest**: a plain data module listing
the page's feature slots, which typed fact goes to which reaction, and the view for each
`live_action`. A generator (`mix zc.gen`) writes the glue into an ordinary **committed** `.ex` file.
That file holds the session struct, a `handle_event` clause per intent, the fact routing and the view
choice. The test alias runs `mix zc.gen --check`, so the build fails if the committed file drifts from
the manifest. Features are pure, emit typed facts, and return effects as data. One interpreter applies
the effects.

The rule behind it: the generated code must be exactly what you would have written by hand, because it
is committed, read and reviewed like any other file. The only macro left is
`use ZeroCoupled.Feature.Intents`, which records intent metadata.

Use it when you want the wiring generated from a diagram and checked against it, but still readable in
the repo. V35 builds on this spine with contracts, presentation purity, flows and calibration in the
manifest.

## At a glance

| | |
|---|---|
| Wiring form | `Manifest`: `features/0` (slot → feature, `render:` port), `reactions/0` (fact → slot reaction), `action_views/0` |
| Generated | `CartPage.Generated` and `CartPage.Session` (about 460 lines), committed; header says "do not edit" |
| Where feature state lives | the generated `%Session{}` in assigns, one field per slot |
| Features | one file each: the pure module, `Facts`, `Intents` (`use ZeroCoupled.Feature.Intents`), `Components` |
| Side effects | `ZeroCoupled.Effects` structs, applied by `EffectInterpreter` |
| Checks | `mix zc.gen --check` in the test alias; `CorePurity` Credo check; `PageCheck.verify/1` in tests |
| Tracing | `mix zc.trace <intent>` prints the intent's owner, its params and the page's reaction table |
| Message hops | none |

## Layers

| Layer | What lives there |
|---|---|
| The diagram | `ZeroCoupledWeb.CartPage.Manifest` |
| Generated glue and shell | `CartPage.Generated` and `CartPage.Session` (generated), `CartPage` (hand-written: mount, irregular events, `run/2`), the action views |
| Features | `ZeroCoupled.Features.*`: `CartItems`, `Undo`, `SavedItems`, `Wishlist`, `CheckoutFlow`, `PageUI` |
| Domain | `ZeroCoupled.Cart` aggregate, `ZeroCoupled.Domain.*` single-function abstractions |
| Platform | `Effects`, `EffectInterpreter`, `Feature.Intents`, `PageCheck`, `Gen.PageGenerator`, the mix tasks, `Credo.CorePurity`, `Foundation.*` |

## Building block 1: a feature, in one file

```elixir
defmodule ZeroCoupled.Features.Undo do          # pure: struct and functions, no Phoenix, no peers
  defstruct pending: nil
  def capture(%__MODULE__{} = undo, item), do: %{undo | pending: %{item: item}}
  def render_data(%__MODULE__{} = undo), do: %{pending?: pending?(undo)}
end

defmodule ZeroCoupled.Features.Undo.Facts do     # typed events it emits
  defmodule ItemRestored do
    @enforce_keys [:item]
    defstruct [:item]
  end
end

defmodule ZeroCoupled.Features.Undo.Intents do   # browser events it owns, reactions it offers
  use ZeroCoupled.Feature.Intents, slot: :undo
  intent :undo_remove
  def undo_remove(session, _args), do: ...     # {session, effects, facts}
  def capture_removed(%Undo{} = undo, %{item: item, item_id: item_id}), do: ...   # {undo, effects}
end
```

- An intent is `(session, args) -> {session, effects}` or `{session, effects, facts}`. It writes its
  own slot through `put_slot/2`.
- `intent name, params: [...]` records metadata the generator uses to write the `handle_event`
  clause with param casts.
- A reaction is slot-scoped, `(slot_state, payload) -> {slot_state, effects}`.
- `Components` hold the feature's markup, and `render_data/1` projects state for the view.

## Building block 2: effects

Intents return `Effects` structs: `flash`, `push`, `stream_insert`, `stream_delete`, `stream_reset`,
`patch`, `navigate`, `redirect_external`, `start_timer`, `cancel_timer`, `persist_quantity`,
`persist_remove`, `start_checkout`, `finalize_order`. `EffectInterpreter.apply_all/3` turns them into socket changes and store calls, so
intents can be tested without a socket.

## Wiring: the manifest

```elixir
def features do
  [
    cart: {CartItems, render: :render_data},
    undo: {Undo, render: :render_data},
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
    {CartFacts.ItemSaved, to: {:saved, SavedItems.Intents, :stash}},
    {UndoFacts.RemovalFinal, to: {:cart, CartItems.Intents, :confirm_removal}},
    {CartFacts.PromoApplied, to: {:ui, PageUI.Intents, :clear_promo_error}},
    {CartFacts.PromoRejected, to: {:ui, PageUI.Intents, :set_promo_error}},
    {CartFacts.AddedFromWishlist, to: {:wishlist, Wishlist.Intents, :drop_product}}
  ]
end

def action_views, do: [index: IndexView, checkout: CheckoutView]
```

The manifest is ordinary Elixir, so a misspelt fact or feature alias is a compile error. Intents aren't
listed here. The generator collects them from each feature's `Intents` module and checks that no two
features claim the same intent.

## The generated glue and the shell

`Generated` holds `Session.new/1`, `run_pure/2`, `intent_owner/1`, `page_event/4` (one clause per
intent), `apply_fact/2` (one clause per reaction), `mount_session/2`, `put_session/2`,
`page_render/1` and `__manifest__/0`.

The hand-written page holds what the manifest can't express:

- the address changeset form;
- events that need I/O first (`pay` reads stock, `add_wishlisted_to_cart` stores a line);
- `handle_async` for the payment;
- the timer and PubSub messages.

Every other event goes to the generated clauses:

```elixir
def handle_event(event, params, socket), do: Generated.page_event(event, params, socket, &run/2)

def handle_info({:undo_expired, item_id}, socket), do: run(socket, &Undo.Intents.undo_expired(&1, item_id))

defp run(socket, fun) do
  {session, effects} = Generated.run_pure(socket.assigns.session, fun)
  {:noreply, socket |> Generated.put_session(session) |> EffectInterpreter.apply_all(effects, effect_opts())}
end
```

`run_pure/2` runs the intent, then routes any facts it emitted through `apply_fact/2`.

## Checks

- The test alias runs `zc.gen --check` before the tests.
- `CorePurity` (Credo) fails if the core references the web layer.
- `PageCheck.verify/1`, a one-line test per page, checks every feature exports `init/1`, every fact is
  a struct, every reaction target is exported and names a declared slot, and param specs use known
  types.

## Applying it to another project

1. Copy the platform: `Effects`, `EffectInterpreter`, `Feature.Intents`, `PageCheck`,
   `Gen.PageGenerator`, the `zc.gen` and `zc.trace` tasks, and `CorePurity`.
2. Write each feature as one file with four modules.
3. Write each page's manifest, run `mix zc.gen`, and commit the generated file.
4. Write the page shell: mount through `Generated.mount_session`, the irregular events, `run/2`.
5. Add `zc.gen --check` to the test alias.

V30's own `docs/adding-a-feature.md` walks through adding a feature.

## Trade-offs and limits

- A generator of about 480 lines to own, and an extra step on every wiring change: edit the manifest,
  then regenerate.
- Store calibration (shipping rates, promo codes) is still baked into the domain modules. V35 moves it
  into the manifest.
- Event and stream names are literals in markup and intents, with no contracts module.
- The timer and stock messages are untyped tuples handled by the shell.
- Reactions are single-level, so an intent that emits a fact in response to a timer has to be a shell
  clause.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/zero_coupled_web/pages/cart_page/manifest.ex` | the diagram |
| `lib/zero_coupled_web/pages/cart_page/generated.ex` | the committed glue |
| `lib/zero_coupled_web/pages/cart_page.ex` | the hand-written shell |
| `lib/zero_coupled/features/undo.ex` | a feature's four modules |
| `lib/zero_coupled/gen/page_generator.ex` | the generator |
| `docs/techniques.md`, `docs/adding-a-feature.md`, `docs/architecture.md` | one recipe per mechanism, a walkthrough, the layer map |
