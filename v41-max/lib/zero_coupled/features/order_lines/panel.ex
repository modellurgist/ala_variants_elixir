defmodule ZeroCoupled.Features.OrderLines.Panel do
  @moduledoc """
  The bulk-order draft as a UI instance: its lines, totals and the review button, owning their
  events and its persistence. Config: `cart_id`, `pricing` (a `Pricing`), `store` (the cart store),
  `add_line` (an `AddLine`), `empty_text`. Inputs: `add: {product,
  quantity}`, `receive: item`, `confirm_removal: id`, `set_stock: change`. Announces `{:order,
  :summary, _}`, `{:order, :removed, item}`, `{:order, :review, summary}`.
  """
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows
  alias ZeroCoupled.Domain.AddLine
  alias ZeroCoupled.Features.OrderLines
  alias ZeroCoupledWeb.Paradigms.Instance

  # outputs this instance shows itself; every other port its feature declares is announced
  @lands_only [:rows, :changed]

  @doc "The ports this instance announces, as `{name, port, payload}`. `:review` is the panel's own (the review button), not a feature port."
  def announces, do: Keyword.keys(OrderLines.ports().out) -- (@lands_only ++ [:review])

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
    do: {:noreply, Instance.announce(s, :order, {:review, s.assigns.summary})}

  defp step(s, fun), do: Instance.step(s, fun, &land/2)
  defp land(s, {:rows, {:reset, rows}}), do: stream(s, :order_lines, rows, reset: true)
  defp land(s, {:rows, {:removed, row}}), do: stream_delete(s, :order_lines, row)
  defp land(s, {:rows, {_, row}}), do: stream_insert(s, :order_lines, row)

  defp land(s, {:summary, summary} = out),
    do: s |> assign(summary: summary) |> Instance.announce(:order, out)

  defp land(s, {:changed, change}),
    do:
      (
        s.assigns.store.apply_change(change)
        s
      )

  defp land(s, out), do: Instance.announce(s, :order, out)

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
