# V36 design: vernacular core

A small, framework-free design that tries to keep ALA's structure while using only ordinary Elixir.
It has no macros, codegen, manifest, runtime library or custom checker. There are three parts:

- **Features** are plain modules with a private struct and pure functions. Each returns its new state
  and a list of **outcomes**, which are side effects described as data.
- **The composition** (`CartPage`) is a struct with one slot per feature, plus one `handle/3` clause
  per user action. Wiring between features is explicit function calls inside those clauses.
- **The shell** (`CartShell`) runs an action through the composition and applies the outcomes at the
  edge.

This variant is a core only: about 340 lines, with no Phoenix. A map stands in for the LiveView
socket. In a real app, a LiveView delegates to the shell in three lines.

Use it when you want the ALA structure (knowledge flowing down, private state per feature, wiring in
one place, calibration at the top) with nothing new to learn. The cost is that the wiring is
imperative code inside `handle/3`, not a list you can check or draw.

## At a glance

| | |
|---|---|
| Wiring form | one `CartPage.handle(action, args, page)` clause per user action, calling features and threading their results |
| Where feature state lives | one field per feature in the `%CartPage{}` struct |
| Side effects | `Shop.Outcome` structs (`Flash`, `StreamInsert`, `StreamDelete`, `StartTimer`, `CancelTimer`, `Patch`), built by constructor functions |
| Runtime | none beyond `CartShell.dispatch/4`, which applies outcomes |
| Calibration | `@pricing` on `CartPage`, passed into the cart and used by the generic `Pricing` functions |
| Checks | `ala_lint` run by hand; no coverage test or diagram |
| Message hops | none |

## Layers

| Layer | Module | What lives there |
|---|---|---|
| Application | `ShopWeb.CartPage` | the composition: calibration, the feature slots, `handle/3`, `assigns/1` view data |
| Shell | `ShopWeb.CartShell` | runs `handle/3` and applies outcomes to the view |
| Features | `Shop.Cart`, `Shop.Wishlist`, `Shop.Undo`, `Shop.Checkout` | a private struct and pure functions each; no peer knowledge |
| Domain and paradigm | `Shop.Pricing`, `Shop.Outcome` | generic price calculations with calibration as data; the effect vocabulary |

## Building block 1: a feature

```elixir
defmodule Shop.Undo do
  alias Shop.Outcome
  defstruct pending: nil, window_ms: 5_000

  def capture(%__MODULE__{} = u, item) do
    {%{u | pending: item},
     [Outcome.start_timer(:undo, u.window_ms, {:undo_expired, item.id}),
      Outcome.flash(:info, "Item removed — undo?")]}
  end

  def take(%__MODULE__{pending: nil} = u), do: {u, nil, []}
  def take(%__MODULE__{pending: item} = u),
    do: {%{u | pending: nil}, item, [Outcome.cancel_timer(:undo), Outcome.flash(:info, "Item restored")]}
end
```

A feature function returns either `{state, outcomes}`, or `{state, value, outcomes}` when the
composition needs a value back (a removed item, a restored item, a validation result). A feature never
calls another feature. When something it did matters to a peer, it returns the value and lets the
composition pass it on.

## Building block 2: the outcome vocabulary

```elixir
def flash(level, message), do: %Flash{level: level, message: message}
def stream_insert(name, item), do: %StreamInsert{name: name, item: item}
def start_timer(name, after_ms, message), do: %StartTimer{name: name, after_ms: after_ms, message: message}
def patch(to), do: %Patch{to: to}
```

Features build outcomes only through these constructors, so a misspelt outcome fails to compile.

## Wiring: the composition

```elixir
@pricing %{
  shipping: %{standard: %{cost: 599, free_above: 5000}, express: %{cost: 1299, free_above: nil}},
  promo: %{"SAVE10" => 10, "HALF" => 50},
  gift_wrap: 299
}

defstruct [:cart, :wishlist, :undo, :checkout]

def handle(:remove_item, %{item_id: id}, s) do
  {cart, removed, outs} = Cart.remove_item(s.cart, id)
  if removed do
    {undo, undo_outs} = Undo.capture(s.undo, removed)
    {%{s | cart: cart, undo: undo}, outs ++ undo_outs}
  else
    {%{s | cart: cart}, outs}
  end
end

def handle(:toggle_wishlist, %{item_id: id}, s) do
  case Cart.find(s.cart, id) do
    nil -> {s, []}
    item ->
      {wl, outs} = Wishlist.toggle(s.wishlist, item.product)
      {%{s | wishlist: wl}, outs}
  end
end

def assigns(%__MODULE__{} = s),
  do: %{cart: Cart.totals(s.cart), undo_pending?: Undo.pending?(s.undo),
        wishlist_count: Wishlist.count(s.wishlist), step: s.checkout.step}
```

Each clause calls one feature, and when the result concerns another feature, it calls that one with
the value. The composition may read across slots (`Cart.find(s.cart, id)`) to hand a feature a value.
It never hands a feature another feature's struct. `assigns/1` turns the slots into plain maps for the
template.

## The shell

```elixir
def dispatch(page, view, action, args) do
  {page, outcomes} = CartPage.handle(action, args, page)
  {page, Enum.reduce(outcomes, view, &apply_outcome/2)}
end
```

`apply_outcome/2` has one clause per outcome struct. In a LiveView, those clauses would call
`put_flash`, `stream_insert`, `Process.send_after` and `push_patch` on the socket. The LiveView's
`handle_event` casts params, calls `dispatch`, and assigns the result.

## Events, timers, store I/O

- **Events:** every browser event becomes one `handle/3` action.
- **Timers:** `StartTimer` carries the message to send back (`{:undo_expired, id}`). That message
  arrives as a `handle/3` action.
- **Store I/O:** none in this core. In a real app, add outcome structs for writes and apply them in the
  shell.

## Applying it to another project

1. Write each feature as a plain module with a private struct. Its functions return
   `{state, outcomes}` or `{state, value, outcomes}`, and it never names a peer.
2. Define an outcome vocabulary as structs with constructor functions, one per kind of side effect your
   app has.
3. Write the composition: a struct with one field per feature, calibration as module attributes passed
   into features, one `handle/3` clause per action, and an `assigns/1` for the view.
4. Write the shell: `dispatch/4` plus one `apply_outcome/2` clause per outcome, called from your
   LiveView's handlers.
5. Run `ala_lint` in CI so the discipline holds.

## Trade-offs and limits

- The wiring holds by discipline only. Nothing checks that every cross-feature consequence is handled.
- Adding an interaction means editing a `handle/3` clause, not adding a row somewhere.
- The `handle/3` clauses contain `if` and `case`, so the composition makes small decisions. The R11
  check flags this as logic in the application layer.
- Features hold some user-facing words (flash texts) and a default undo window. Strict R3 would move
  both up to the composition.
- It's a core, not a running app: there are no stores, payment, URLs or PubSub here.

## Where to look in this repo

| File | What it shows |
|---|---|
| `lib/shop_web/cart_page.ex` | the composition |
| `lib/shop_web/cart_shell.ex` | the shell and the three-line LiveView delegation |
| `lib/shop/outcome.ex` | the outcome vocabulary |
| `lib/shop/cart.ex`, `undo.ex`, `wishlist.ex`, `checkout.ex` | the features |
| `test/cart_page_test.exs` | actions run through the composition |
