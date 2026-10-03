defmodule ZeroCoupled.Features.Cart.Panel do
  @moduledoc """
  The cart as a UI instance: its lines, totals, shipping and promo, owning their events. It loads
  through `source`, a read the page wires in, and sends every change out for the page to store.
  Config: `cart_id`, `pricing` (a `Pricing`), `source`, `gift_wrap_label`, `empty_text`,
  `invalid_promo_text`, `wishlist_ids`. Inputs by `send_update`: `receive: item`,
  `confirm_removal: id`, `set_stock: change`. Sends the page `{:cart, port, payload}` for every port
  it doesn't show itself: `:summary`, `:removed`, `:saved`, `:line`, `:changed`, `:promo_applied`,
  `:promo_rejected`.
  """
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows
  alias ZeroCoupled.Features.Cart
  alias ZeroCoupledWeb.Paradigms.Instance

  # outputs this instance shows itself; every other port its feature declares is sent
  @wired_here [:rows]

  @doc "The ports this instance sends the page, as `{name, port, payload}`."
  def sent_port_outputs, do: Keyword.keys(Cart.ports().out) -- @wired_here

  def mount(socket), do: {:ok, socket |> stream(:cart_items, []) |> assign(promo_error: nil)}

  def update(%{receive: item}, s), do: {:ok, step(s, &Cart.receive(&1, item))}
  def update(%{confirm_removal: id}, s), do: {:ok, step(s, &Cart.confirm_removal(&1, id))}
  def update(%{set_stock: change}, s), do: {:ok, step(s, &Cart.set_stock(&1, change))}

  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_loaded()}

  defp ensure_loaded(%{assigns: %{state: _}} = s), do: s

  # `source` is a pull port the page wires to a read: this instance never names a store
  defp ensure_loaded(%{assigns: %{cart_id: cart_id, pricing: pricing, source: source}} = s) do
    s
    |> assign(state: ZeroCoupled.Cart.new(cart_id: cart_id, pricing: pricing))
    |> step(&Cart.load(&1, source.(cart_id)))
  end

  def handle_event("update_quantity", %{"item-id" => id, "delta" => d}, s),
    do: {:noreply, step(s, &Cart.update_quantity(&1, %{item_id: int(id), delta: int(d)}))}

  def handle_event("remove_item", %{"item-id" => id}, s),
    do: {:noreply, step(s, &Cart.remove(&1, %{item_id: int(id)}))}

  def handle_event("save_for_later", %{"item-id" => id}, s),
    do: {:noreply, step(s, &Cart.save_for_later(&1, %{item_id: int(id)}))}

  def handle_event("toggle_gift_wrap", %{"item-id" => id}, s),
    do: {:noreply, step(s, &Cart.toggle_gift_wrap(&1, %{item_id: int(id)}))}

  def handle_event("toggle_wishlist", %{"item-id" => id}, s),
    do: {:noreply, step(s, &Cart.line(&1, %{item_id: int(id)}))}

  def handle_event("select_shipping", %{"method" => m}, s),
    do: {:noreply, step(s, &Cart.select_shipping(&1, %{method: String.to_existing_atom(m)}))}

  def handle_event("apply_promo", %{"code" => code}, s),
    do: {:noreply, step(s, &Cart.apply_promo(&1, %{code: code}))}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)

  defp wire(s, {:rows, {:reset, rows}}), do: stream(s, :cart_items, rows, reset: true)
  defp wire(s, {:rows, {:removed, row}}), do: stream_delete(s, :cart_items, row)
  defp wire(s, {:rows, {_, row}}), do: stream_insert(s, :cart_items, row)

  defp wire(s, {:summary, summary} = out),
    do: s |> assign(summary: summary) |> Instance.send_port_output(:cart, out)

  defp wire(s, {:promo_applied, _} = out),
    do: s |> assign(promo_error: nil) |> Instance.send_port_output(:cart, out)

  defp wire(s, {:promo_rejected, _} = out),
    do:
      s
      |> assign(promo_error: s.assigns.invalid_promo_text)
      |> Instance.send_port_output(:cart, out)

  defp wire(s, out), do: Instance.send_port_output(s, :cart, out)

  defp int(str), do: String.to_integer(str)

  def render(assigns) do
    ~H"""
    <div>
      <div id="cart_items" phx-update="stream">
        <.cart_item_row
          :for={{dom_id, row} <- @streams.cart_items}
          id={dom_id}
          row={row}
          target={@myself}
          wishlisted={row.product_id in @wishlist_ids}
          gift_wrap_label={@gift_wrap_label}
          t={@t.row}
          on_quantity="update_quantity"
          on_remove="remove_item"
          on_gift_wrap="toggle_gift_wrap"
          on_save="save_for_later"
          on_wishlist="toggle_wishlist"
        />
      </div>
      <div :if={@summary.empty?} class="py-12 text-center text-zinc-400">{@empty_text}</div>

      <div class="space-y-2 py-6 border-t mt-6">
        <div class="flex justify-between text-zinc-600">
          <span>{@t.items}</span><span>{@summary.item_count}</span>
        </div>
        <div class="flex justify-between text-zinc-600">
          <span>{@t.subtotal}</span><span>{@summary.subtotal}</span>
        </div>
        <div :if={@summary.promo_code} class="flex justify-between text-green-600">
          <span>{@t.discount} ({@summary.promo_code})</span><span>-{@summary.discount}</span>
        </div>
        <div
          :if={Money.positive?(@summary.gift_wrap_total)}
          class="flex justify-between text-zinc-600"
        >
          <span>{@t.gift_wrap}</span><span>{@summary.gift_wrap_total}</span>
        </div>
        <div class="flex justify-between text-zinc-600">
          <span>{@t.shipping} ({@summary.shipping_label})</span>
          <span>
            {if Money.zero?(@summary.shipping_cost), do: @t.free, else: @summary.shipping_cost}
          </span>
        </div>
        <div class="flex justify-between items-center py-3 border-t-2 font-bold text-xl">
          <span>{@t.total}</span><span>{@summary.total}</span>
        </div>
      </div>
      <div class="py-2">
        <h3 class="text-sm font-semibold text-zinc-700 mb-2">{@t.shipping}</h3>
        <div class="flex gap-2">
          <label
            :for={opt <- @summary.shipping_options}
            class="flex items-center gap-2 p-2 border rounded cursor-pointer text-sm"
          >
            <input
              type="radio"
              name="shipping_method"
              value={opt.method}
              checked={@summary.shipping_method == opt.method}
              phx-click="select_shipping"
              phx-value-method={opt.method}
              phx-target={@myself}
            />
            {opt.label}
            <span class="text-zinc-400">
              {opt.cost}<span :if={opt.free_above}> ({@t.free_over} {opt.free_above})</span>
            </span>
          </label>
        </div>
      </div>
      <form phx-submit="apply_promo" phx-target={@myself} class="flex gap-2 py-4">
        <input
          type="text"
          name="code"
          placeholder={@t.promo_placeholder}
          value={@summary.promo_code || ""}
          class="rounded border border-zinc-300 px-3 py-1.5 text-sm"
        />
        <button type="submit" class="rounded bg-zinc-200 px-4 py-1.5 text-sm font-medium">
          {@t.apply}
        </button>
        <span :if={@promo_error} class="text-red-500 text-sm self-center">{@promo_error}</span>
      </form>
    </div>
    """
  end
end
