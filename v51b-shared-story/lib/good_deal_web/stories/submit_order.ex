defmodule GoodDealWeb.Stories.SubmitOrder do
  @moduledoc """
  The buyer reviews the order, gives a purchase order number and submits it, which places the order.
  Its part is the portal's review flow; its view is the review form and the submitted order. The flow,
  its URLs and its messages are this story's own. Out: `:step`, `:form`, `:po`, `:reference`.
  """
  use GoodDealWeb, :html
  import Phoenix.LiveView, only: [put_flash: 3]
  import GoodDeal.Components.Panes, only: [only_on: 1]
  import GoodDeal.Components.Parts, only: [card: 1]
  import GoodDeal.Components.Rows, only: [order_summary: 1]

  alias GoodDeal.Domain.PlaceOrder
  alias GoodDeal.State.PortalSubmit
  alias GoodDeal.Foundation.Orders
  alias GoodDealWeb.Paradigms.Steps

  @flow [
    {:lines, :go_review, :review},
    {:review, :edit_lines, :lines},
    {:review, :submit_order, :submitted}
  ]
  @url_edges [{:review, :lines}]
  @step_paths %{lines: "/portal", review: "/portal/review", submitted: "/portal/submitted"}
  @blocked %{empty: "Your order is empty"}

  def parts, do: %{flow: PortalSubmit}
  def events, do: ~w(edit_lines validate_po submit_order)

  def ports,
    do: %{
      in: [review: :summary, goto: :step],
      out: [step: :step, form: :changeset, po: :po, reference: :order_id]
    }

  @doc "Config: `cart_id`, the order to place."
  def mount(s, opts, out) do
    flow =
      PortalSubmit.new(
        flow: @flow,
        start: :lines,
        url_edges: @url_edges,
        messages: %{number: "must look like PO-1234"}
      )

    s
    |> assign(flow: flow, place_order: %PlaceOrder{orders: Orders, cart_id: opts[:cart_id]})
    |> run(&PortalSubmit.show_form(&1, nil), out)
  end

  def input(s, :review, summary, out), do: run(s, &PortalSubmit.review(&1, summary), out)
  def input(s, :goto, step, out), do: run(s, &PortalSubmit.goto(&1, step), out)

  def handle_event("edit_lines", _params, s, out),
    do: run(s, &PortalSubmit.edit_lines(&1, nil), out)

  def handle_event("validate_po", %{"po" => params}, s, out),
    do: run(s, &PortalSubmit.validate(&1, params), out)

  def handle_event("submit_order", %{"po" => params}, s, out),
    do: run(s, &PortalSubmit.submit(&1, params), out)

  defp run(s, step, out), do: Steps.run(s, :flow, step, &wire(&1, &2, &3, out))

  defp feed(s, input, source, payload, out),
    do: Steps.feed(s, :flow, input, source, payload, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :flow, {:step, step}, out),
    do: s |> Steps.patch(@step_paths, step) |> out.({:step, step})

  defp wire(s, :flow, {:form, changeset}, out), do: out.(s, {:form, changeset})
  defp wire(s, :flow, {:blocked, reason}, _out), do: put_flash(s, :error, @blocked[reason])

  defp wire(s, :flow, {:approved, po}, out),
    do:
      s
      |> out.({:po, po})
      |> feed(&PortalSubmit.complete/2, &PlaceOrder.place(s.assigns.place_order, &1), po, out)

  defp wire(s, :flow, {:reference, order_id}, out),
    do: s |> out.({:reference, order_id}) |> put_flash(:info, "Order submitted")

  attr :step, :atom, required: true
  attr :form, :any, required: true
  attr :summary, :map, required: true
  attr :order_id, :any, default: nil
  attr :po, :map, default: nil
  attr :t, :map, required: true

  def view(assigns) do
    ~H"""
    <.only_on current={@step} name={:review}>
      <.card class="max-w-lg">
        <div class="mb-6">
          <.order_summary summary={@summary} t={@t.summary} />
        </div>
        <.simple_form for={@form} phx-change="validate_po" phx-submit="submit_order">
          <.input field={@form[:number]} label={@t.po_number} placeholder={@t.po_placeholder} />
          <.input field={@form[:notes]} label={@t.notes} />
          <:actions>
            <button
              type="button"
              phx-click="edit_lines"
              class="text-sm font-medium text-stone-500 hover:text-stone-800"
            >
              {@t.back}
            </button>
            <.button phx-disable-with={@t.submitting}>{@t.submit} · {@summary.total}</.button>
          </:actions>
        </.simple_form>
      </.card>
    </.only_on>
    <.only_on current={@step} name={:submitted}>
      <.card class="max-w-lg">
        <h2 class="pb-2 text-2xl font-semibold">{@t.submitted}</h2>
        <p class="text-stone-600">
          {@t.reference} <span class="font-mono">#{@order_id}</span> · {@po.number}
        </p>
        <p class="pt-1 text-sm text-stone-500">
          {@t.total} {@summary.total} ({@summary.item_count} {@t.items})
        </p>
      </.card>
    </.only_on>
    """
  end
end
