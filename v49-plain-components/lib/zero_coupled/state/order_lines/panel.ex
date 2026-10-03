defmodule ZeroCoupled.State.OrderLines.Panel do
  @moduledoc """
  The bulk-order draft as a UI instance: its lines, totals and the review button, owning their
  events. It loads through `source`, a read the page wires in, and sends every change out for the
  page to store. Config: `cart_id`, `pricing` (a `Pricing`), `source`, `empty_text`. Inputs:
  `add: {line, quantity}`, `receive: item`, `confirm_removal: id`, `set_stock: change`. Sends the
  page `{name, :summary, _}`, `{name, :removed, item}`, `{name, :changed, change}`,
  `{name, :review, summary}`.
  """
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows
  alias ZeroCoupled.State.OrderLines
  alias ZeroCoupledWeb.Paradigms.Instance

  # outputs this instance shows itself; every other port its feature declares is sent
  @wired_here [:rows]

  @doc "The ports this instance sends the page, as `{name, port, payload}`."
  def sent_port_outputs, do: Keyword.keys(OrderLines.ports().out) -- @wired_here

  def mount(socket), do: {:ok, stream(socket, :order_lines, [])}

  def update(%{add: {line, quantity}}, s),
    do: {:ok, step(s, &OrderLines.add(&1, {line, quantity}))}

  def update(%{receive: item}, s), do: {:ok, step(s, &OrderLines.receive(&1, item))}
  def update(%{confirm_removal: id}, s), do: {:ok, step(s, &OrderLines.confirm_removal(&1, id))}
  def update(%{set_stock: change}, s), do: {:ok, step(s, &OrderLines.set_stock(&1, change))}
  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_loaded()}

  defp ensure_loaded(%{assigns: %{state: _}} = s), do: s

  defp ensure_loaded(%{assigns: %{cart_id: cart_id, pricing: pricing, source: source}} = s) do
    s
    |> assign(state: OrderLines.new(cart_id: cart_id, pricing: pricing))
    |> step(&OrderLines.load(&1, source.(cart_id)))
  end

  def handle_event("set_line_quantity", %{"item-id" => id, "quantity" => q}, s),
    do: {:noreply, step(s, &OrderLines.set_quantity(&1, %{item_id: int(id), quantity: int(q)}))}

  def handle_event("remove_line", %{"item-id" => id}, s),
    do: {:noreply, step(s, &OrderLines.remove(&1, %{item_id: int(id)}))}

  def handle_event("go_review", _, s),
    do: {:noreply, step(s, &OrderLines.request_review(&1, nil))}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)
  defp wire(s, {:rows, {:reset, rows}}), do: stream(s, :order_lines, rows, reset: true)
  defp wire(s, {:rows, {:removed, row}}), do: stream_delete(s, :order_lines, row)
  defp wire(s, {:rows, {_, row}}), do: stream_insert(s, :order_lines, row)

  defp wire(s, {:summary, summary} = out),
    do: s |> assign(summary: summary) |> Instance.send_port_output(s.assigns.name, out)

  defp wire(s, out), do: Instance.send_port_output(s, s.assigns.name, out)

  defp int(str), do: String.to_integer(str)

  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-semibold pb-2">{@t.heading}</h2>
      <div id="order_lines" phx-update="stream">
        <.order_line_row
          :for={{dom_id, row} <- @streams.order_lines}
          id={dom_id}
          row={row}
          target={@myself}
          on_quantity="set_line_quantity"
          on_remove="remove_line"
          t={@t.row}
        />
      </div>
      <div :if={@summary.empty?} class="py-8 text-center text-zinc-400">{@empty_text}</div>
      <.order_summary summary={@summary} t={@t.summary} />
      <button
        phx-click="go_review"
        phx-target={@myself}
        disabled={@summary.empty?}
        class={[
          "rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-4 text-sm font-semibold text-white",
          @summary.empty? && "opacity-50 cursor-not-allowed"
        ]}
      >
        {@t.review} · {@summary.total}
      </button>
    </section>
    """
  end
end
