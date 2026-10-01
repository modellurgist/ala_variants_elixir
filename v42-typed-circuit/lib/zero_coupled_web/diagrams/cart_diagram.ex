defmodule ZeroCoupledWeb.CartDiagram do
  @moduledoc """
  The cart page's diagram: every instance, its configuration (the store's literals included), and
  every wire, as one data expression. `mix circuit.draw` renders it; `Circuit.validate!/1` checks
  it. The page passes what only it can supply: the cart id and the payment function.
  """
  alias ZeroCoupled.Domain.{
    AddLine,
    CalculateGiftWrapCost,
    CalculateShipping,
    PlaceOrder,
    ValidatePromo
  }

  alias ZeroCoupled.Features.{Cart, Checkout, PageUI, SavedItems, Undo, Wishlist}
  alias ZeroCoupled.Foundation.{Broadcast, Carts, Orders, Products}

  alias ZeroCoupled.Paradigms.{
    Adapter,
    Circuit,
    FromStore,
    ToAssign,
    ToAsync,
    ToComponent,
    ToFlash,
    ToForm,
    ToPatch,
    ToRedirect,
    ToStore,
    ToTimer
  }

  alias ZeroCoupledWeb.CartLive.{CartPanel, SavedPanel, WishlistPanel}

  @rates %{
    standard: %{label: "Standard (5–7 days)", cost: 599, free_above: 5000},
    express: %{label: "Express (2–3 days)", cost: 1299, free_above: nil},
    overnight: %{label: "Overnight", cost: 2499, free_above: nil}
  }
  @promo_codes %{"SAVE10" => 10, "SAVE20" => 20, "HALF" => 50}
  @gift_wrap_unit 299
  @undo_window_ms 5_000
  @checkout_flow [
    {:address, :submit_address, :payment},
    {:payment, :edit_address, :address},
    {:payment, :pay, :processing},
    {:error, :pay, :processing}
  ]
  @checkout_url_edges [{:payment, :address}]
  @step_paths %{address: "/cart/checkout", payment: "/cart/checkout/payment"}
  @blocked %{empty: "Your cart is empty", out_of_stock: "Some items are out of stock"}

  def circuit(%{cart_id: cart_id, charge: charge}) do
    Circuit.new(
      lines: %FromStore{read: &Carts.list_items/1, type: :items},
      cart:
        Adapter.new(
          Cart,
          Cart.new(
            cart_id: cart_id,
            pricing: %{
              shipping: CalculateShipping.new(@rates),
              promo: ValidatePromo.new(@promo_codes),
              gift_wrap: CalculateGiftWrapCost.new(@gift_wrap_unit)
            }
          )
        ),
      undo: Adapter.new(Undo, Undo.new([])),
      saved: Adapter.new(SavedItems, SavedItems.new([])),
      wishlist: Adapter.new(Wishlist, Wishlist.new([])),
      ui: Adapter.new(PageUI, PageUI.new(tabs: [:items, :saved, :wishlist])),
      checkout:
        Adapter.new(
          Checkout,
          Checkout.new(
            flow: @checkout_flow,
            start: :address,
            url_edges: @checkout_url_edges,
            stock_levels: &Products.stock_levels/1
          )
        ),
      add_line: %AddLine{carts: Carts, products: Products, cart_id: cart_id},
      place_order: %PlaceOrder{
        orders: Orders,
        carts: Carts,
        products: Products,
        announce: &Broadcast.stock_changed/2,
        cart_id: cart_id
      },
      cart_rows: %ToComponent{module: CartPanel, id: "cart"},
      saved_rows: %ToComponent{module: SavedPanel, id: "saved"},
      wishlist_rows: %ToComponent{module: WishlistPanel, id: "wishlist"},
      summary: %ToAssign{name: :summary},
      persist: %ToStore{write: &Carts.apply_change/1},
      saved_count: %ToAssign{name: :saved_count},
      wishlist_count: %ToAssign{name: :wishlist_count},
      wishlist_ids: %ToAssign{name: :wishlist_ids},
      promo_ok: %ToAssign{name: :promo_error, value: nil},
      promo_bad: %ToAssign{name: :promo_error, value: "Invalid promo code"},
      undo_armed: %ToAssign{name: :undo_pending, value: true},
      undo_cleared: %ToAssign{name: :undo_pending, value: false},
      undo_clock: %ToTimer{name: :undo, ms: @undo_window_ms, into: {:undo, :expire}},
      tab: %ToAssign{name: :active_tab},
      step: %ToAssign{name: :step},
      url: %ToPatch{paths: @step_paths},
      address_form: %ToForm{name: :address_form},
      address: %ToAssign{name: :address},
      charge: %ToAsync{
        name: :payment,
        fun: charge,
        ok: {:checkout, :succeeded},
        error: {:checkout, :failed}
      },
      go: %ToRedirect{},
      saved_notice: %ToFlash{text: "Saved for later"},
      moved_notice: %ToFlash{text: "Moved to cart"},
      promo_notice: %ToFlash{text: "Promo applied!"},
      promo_error: %ToFlash{level: :error, text: "Invalid promo code"},
      restored_notice: %ToFlash{text: "Item restored"},
      wishlisted_notice: %ToFlash{text: "Added to wishlist"},
      unwishlisted_notice: %ToFlash{text: "Removed from wishlist"},
      added_notice: %ToFlash{text: "Added to cart"},
      blocked_notice: %ToFlash{level: :error, texts: @blocked}
    )
    |> Circuit.wire({:lines, :loaded}, {:cart, :load})
    |> Circuit.wire({:cart, :rows}, {:cart_rows, :change})
    |> Circuit.wire({:cart, :summary}, {:summary, :value})
    |> Circuit.wire({:cart, :persist}, {:persist, :value})
    |> Circuit.wire({:cart, :removed}, {:undo, :capture})
    |> Circuit.wire({:cart, :saved}, {:saved, :stash})
    |> Circuit.wire({:cart, :saved}, {:saved_notice, :show})
    |> Circuit.wire({:cart, :promo_applied}, {:promo_ok, :value})
    |> Circuit.wire({:cart, :promo_applied}, {:promo_notice, :show})
    |> Circuit.wire({:cart, :promo_rejected}, {:promo_bad, :value})
    |> Circuit.wire({:cart, :promo_rejected}, {:promo_error, :show})
    |> Circuit.wire({:cart, :line}, {:wishlist, :toggle})
    |> Circuit.wire({:cart, :checkout_requested}, {:checkout, :pay})
    |> Circuit.wire({:undo, :captured}, {:undo_armed, :value})
    |> Circuit.wire({:undo, :timer}, {:undo_clock, :value})
    |> Circuit.wire({:undo, :restored}, {:cart, :receive})
    |> Circuit.wire({:undo, :restored}, {:restored_notice, :show})
    |> Circuit.wire({:undo, :restored}, {:undo_cleared, :value})
    |> Circuit.wire({:undo, :expired}, {:cart, :confirm_removal})
    |> Circuit.wire({:undo, :expired}, {:undo_cleared, :value})
    |> Circuit.wire({:saved, :rows}, {:saved_rows, :change})
    |> Circuit.wire({:saved, :count}, {:saved_count, :value})
    |> Circuit.wire({:saved, :moved}, {:cart, :receive})
    |> Circuit.wire({:saved, :moved}, {:moved_notice, :show})
    |> Circuit.wire({:wishlist, :rows}, {:wishlist_rows, :change})
    |> Circuit.wire({:wishlist, :count}, {:wishlist_count, :value})
    |> Circuit.wire({:wishlist, :ids}, {:wishlist_ids, :value})
    |> Circuit.wire({:wishlist, :added}, {:wishlisted_notice, :show})
    |> Circuit.wire({:wishlist, :dropped}, {:unwishlisted_notice, :show})
    |> Circuit.wire({:wishlist, :taken}, {:add_line, :add})
    |> Circuit.wire({:add_line, :line}, {:cart, :receive})
    |> Circuit.wire({:add_line, :line}, {:added_notice, :show})
    |> Circuit.wire({:ui, :tab}, {:tab, :value})
    |> Circuit.wire({:checkout, :step}, {:step, :value})
    |> Circuit.wire({:checkout, :step}, {:url, :value})
    |> Circuit.wire({:checkout, :form}, {:address_form, :value})
    |> Circuit.wire({:checkout, :address}, {:address, :value})
    |> Circuit.wire({:checkout, :blocked}, {:blocked_notice, :show})
    |> Circuit.wire({:checkout, :payment}, {:charge, :value})
    |> Circuit.wire({:checkout, :done}, {:place_order, :place})
    |> Circuit.wire({:checkout, :done}, {:go, :url})
    |> Circuit.ground({:add_line, :line_with_quantity})
    |> Circuit.ground({:place_order, :placed})
  end
end
