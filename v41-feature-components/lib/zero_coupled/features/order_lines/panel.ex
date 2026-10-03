defmodule ZeroCoupled.Features.OrderLines.Panel do
  @moduledoc """
  The bulk-order draft as a UI instance: its lines, totals and the review button, owning their
  events and its persistence. Config: `cart_id`, `pricing` (a `Pricing`), `store` (the cart store),
  `add_line` (an `AddLine`), `empty_text`. Inputs: `add: {product,
  quantity}`, `receive: item`, `confirm_removal: id`, `set_stock: change`. Sends the page `{:order,
  :summary, _}`, `{:order, :removed, item}`, `{:order, :review, summary}`.
  """
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows
  alias ZeroCoupled.Domain.AddLine
  alias ZeroCoupled.Features.OrderLines
  alias ZeroCoupledWeb.Paradigms.Instance

  @doc "The ports this instance sends the page, as `{:order, port, payload}`."
  def sent_port_outputs, do: [:summary, :removed, :review]

  def mount(socket), do: {:ok, stream(socket, :order_lines, [])}

  def update(%{add: {product, quantity}}, s),
    do:
      {:ok,
       step(
         s,
         &OrderLines.add(
           &1,
           {AddLine.run(s.assigns.add_line, s.assigns.cart_id, product), quantity}
         )
       )}

  def update(%{receive: item}, s), do: {:ok, step(s, &OrderLines.receive(&1, item))}
  def update(%{confirm_removal: id}, s), do: {:ok, step(s, &OrderLines.confirm_removal(&1, id))}
  def update(%{set_stock: change}, s), do: {:ok, step(s, &OrderLines.set_stock(&1, change))}
  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_loaded()}

  defp ensure_loaded(%{assigns: %{state: _}} = s), do: s

  defp ensure_loaded(%{assigns: %{cart_id: cart_id, pricing: pricing, store: store}} = s) do
    s
    |> assign(state: OrderLines.new(cart_id: cart_id, pricing: pricing))
    |> step(&OrderLines.load(&1, store.list_items(cart_id)))
  end

  def handle_event("set_line_quantity", %{"item-id" => id, "quantity" => q}, s),
    do: {:noreply, step(s, &OrderLines.set_quantity(&1, %{item_id: int(id), quantity: int(q)}))}

  def handle_event("remove_line", %{"item-id" => id}, s),
    do: {:noreply, step(s, &OrderLines.remove(&1, %{item_id: int(id)}))}

  def handle_event("go_review", _, s),
    do: {:noreply, Instance.send_port_output(s, :order, {:review, s.assigns.summary})}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)
  defp wire(s, {:rows, {:reset, rows}}), do: stream(s, :order_lines, rows, reset: true)
  defp wire(s, {:rows, {:removed, row}}), do: stream_delete(s, :order_lines, row)
  defp wire(s, {:rows, {_, row}}), do: stream_insert(s, :order_lines, row)

  defp wire(s, {:summary, summary} = out),
    do: s |> assign(summary: summary) |> Instance.send_port_output(:order, out)

  defp wire(s, {:persist, change}),
    do:
      (
        s.assigns.store.apply_change(change)
        s
      )

  defp wire(s, out), do: Instance.send_port_output(s, :order, out)

  defp int(str), do: String.to_integer(str)

  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-semibold pb-2">Your order</h2>
      <div id="order_lines" phx-update="stream">
        <.order_line_row
          :for={{dom_id, row} <- @streams.order_lines}
          id={dom_id}
          row={row}
          target={@myself}
          on_quantity="set_line_quantity"
          on_remove="remove_line"
        />
      </div>
      <div :if={@summary.empty?} class="py-8 text-center text-zinc-400">{@empty_text}</div>
      <.order_summary summary={@summary} />
      <button
        phx-click="go_review"
        phx-target={@myself}
        disabled={@summary.empty?}
        class={[
          "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
          @summary.empty? && "opacity-50 cursor-not-allowed"
        ]}
      >
        Review order · {@summary.total}
      </button>
    </section>
    """
  end
end
