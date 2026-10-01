defmodule ZeroCoupledWeb.CartLive.IndexView do
  @moduledoc "The cart page's markup: the tabs, the three lists, the summary, shipping, promo, checkout."
  use ZeroCoupledWeb, :html
  import ZeroCoupled.Catalog.Rows
  import ZeroCoupled.Catalog.{Panes, Parts}

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-6">
      <h1 class="text-4xl pb-4 font-semibold">Your Cart</h1>

      <.notice
        shown={@undo_pending}
        text={@texts.undo.text}
        action={@texts.undo.undo}
        event="undo_remove"
      />
      <.tabs current={@active_tab} event="switch_tab">
        <:tab name={:items} label={"#{@texts.tabs.items} (#{@summary.item_count})"} />
        <:tab name={:saved} label={"#{@texts.tabs.saved} (#{@saved_count})"} />
        <:tab name={:wishlist} label={"#{@texts.tabs.wishlist} (#{@wishlist_count})"} />
      </.tabs>

      <.pane current={@active_tab} name={:items}>
        <.stream_list :let={{dom_id, row}} id="cart_items" stream={@streams.cart_items}>
          <.cart_item_row
            id={dom_id}
            row={row}
            wishlist_ids={@wishlist_ids}
            gift_wrap_label={@texts.cart.gift_wrap_label}
            t={@texts.cart.row}
            on_quantity="update_quantity"
            on_remove="remove_item"
            on_gift_wrap="toggle_gift_wrap"
            on_save="save_for_later"
            on_wishlist="toggle_wishlist"
          />
        </.stream_list>
        <.none count={@summary.item_count} text={@texts.cart.empty} />
      </.pane>

      <.pane current={@active_tab} name={:saved}>
        <.stream_list :let={{dom_id, row}} id="saved_items" stream={@streams.saved_items}>
          <.saved_row
            id={dom_id}
            row={row}
            t={@texts.saved.row}
            on_move="move_to_cart"
          />
        </.stream_list>
        <.none count={@saved_count} text={@texts.saved.empty} />
      </.pane>

      <.pane current={@active_tab} name={:wishlist}>
        <.stream_list :let={{dom_id, row}} id="wishlist_products" stream={@streams.wishlist_products}>
          <.wishlist_row
            id={dom_id}
            row={row}
            t={@texts.wishlist.row}
            on_add="add_wishlisted_to_cart"
            on_remove="remove_wishlist"
          />
        </.stream_list>
        <.none count={@wishlist_count} text={@texts.wishlist.empty} />
      </.pane>

      <.cart_summary summary={@summary} t={@texts.cart} />
      <.shipping_selector
        summary={@summary}
        heading={@texts.cart.shipping}
        free_over={@texts.cart.free_over}
        event="select_shipping"
      />
      <.promo_form
        code={@summary.promo_code}
        error={@promo_error}
        event="apply_promo"
        t={@texts.cart}
      />
      <div class="py-4">
        <.primary_button event="start_checkout" disabled={@summary.empty?}>
          {@texts.cart.checkout} · {@summary.total}
        </.primary_button>
      </div>
    </div>
    """
  end
end
