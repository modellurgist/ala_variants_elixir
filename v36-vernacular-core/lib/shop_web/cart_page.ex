defmodule ShopWeb.CartPage do
  @moduledoc """
  The composition — V36's "application layer". This is the only module that
  knows the cart page is made of *these* features and how they connect. It is
  ordinary Elixir: a struct with one slot per feature (each a private
  per-feature struct → state independence), plus one `handle/3` clause per user
  action. Cross-feature coordination is **explicit function calls, in this one
  place** — no manifest, no facts, no macros, no codegen. Reading `handle/3`
  reads the page's behaviour top to bottom.

  Calibration lives here too (the `@pricing` "diagram config"), injected into
  the generic `Pricing` calcs via the cart's `pricing:` — so the domain layer
  stays product-free.
  """
  alias Shop.{Cart, Wishlist, Undo, Checkout}

  # ── Calibration on the diagram (what makes this THIS store) ──────────────
  @pricing %{
    shipping: %{
      standard: %{cost: 599, free_above: 5000},
      express: %{cost: 1299, free_above: nil}
    },
    promo: %{"SAVE10" => 10, "HALF" => 50},
    gift_wrap: 299
  }

  defstruct [:cart, :wishlist, :undo, :checkout]

  def new(opts \\ []) do
    %__MODULE__{
      cart: Cart.new(Keyword.put(opts, :pricing, @pricing)),
      wishlist: Wishlist.new(),
      undo: Undo.new(),
      checkout: Checkout.new()
    }
  end

  # ── One clause per action. The wiring is right here, in plain sight. ─────

  def handle(:update_quantity, %{item_id: id, delta: d}, s) do
    {cart, outs} = Cart.update_quantity(s.cart, id, d)
    {%{s | cart: cart}, outs}
  end

  def handle(:remove_item, %{item_id: id}, s) do
    {cart, removed, outs} = Cart.remove_item(s.cart, id)
    if removed do
      {undo, undo_outs} = Undo.capture(s.undo, removed)     # cross-feature follow-up: explicit
      {%{s | cart: cart, undo: undo}, outs ++ undo_outs}
    else
      {%{s | cart: cart}, outs}
    end
  end

  def handle(:undo_remove, _args, s) do
    {undo, item, outs} = Undo.take(s.undo)
    if item do
      {cart, cart_outs} = Cart.add_item(s.cart, item)       # restore into the cart: explicit
      {%{s | cart: cart, undo: undo}, outs ++ cart_outs}
    else
      {%{s | undo: undo}, outs}
    end
  end

  def handle(:undo_expired, %{item_id: _id}, s) do
    {undo, outs} = Undo.clear(s.undo)
    {%{s | undo: undo}, outs}
  end

  def handle(:toggle_wishlist, %{item_id: id}, s) do
    case Cart.find(s.cart, id) do                            # composition reads across slots (allowed)
      nil -> {s, []}
      item ->
        {wl, outs} = Wishlist.toggle(s.wishlist, item.product)  # feature gets a value, not a peer slot
        {%{s | wishlist: wl}, outs}
    end
  end

  def handle(:toggle_gift_wrap, %{item_id: id}, s) do
    {cart, outs} = Cart.toggle_gift_wrap(s.cart, id)
    {%{s | cart: cart}, outs}
  end

  def handle(:select_shipping, %{method: m}, s) do
    {cart, outs} = Cart.select_shipping(s.cart, m)
    {%{s | cart: cart}, outs}
  end

  def handle(:apply_promo, %{code: code}, s) do
    {cart, outs, _result} = Cart.apply_promo(s.cart, code)
    {%{s | cart: cart}, outs}
  end

  def handle(:start_checkout, _args, s) do
    {co, outs} = Checkout.start(s.checkout, Cart.empty?(s.cart))
    {%{s | checkout: co}, outs}
  end

  def handle(:submit_address, %{address: addr}, s) do
    {co, outs, _result} = Checkout.submit_address(s.checkout, addr)
    {%{s | checkout: co}, outs}
  end

  @doc "View data — plain maps a template reads; no feature or domain module in the view."
  def assigns(%__MODULE__{} = s) do
    %{
      cart: Cart.totals(s.cart),
      undo_pending?: Undo.pending?(s.undo),
      wishlist_count: Wishlist.count(s.wishlist),
      step: s.checkout.step
    }
  end
end
