defmodule ZeroCoupled.Features.PortalSubmit.Panel do
  @moduledoc """
  The review and confirmation screens as a UI instance: the PO form, and the order it places
  when approved. Config: `cart_id`, `place_order` (a `PlaceOrder`), `messages` (the PO form's), `flow`, `start`, `url_edges`, `summary`,
  `requested_step`. Input: `review: summary`. Announces `{:submit, :step, step}`,
  `{:submit, :blocked, reason}`, `{:submit, :reference, order_id}`.
  """
  use ZeroCoupledWeb, :live_component
  import ZeroCoupled.Catalog.Rows, only: [order_summary: 1]
  alias ZeroCoupled.Domain.PlaceOrder
  alias ZeroCoupled.Features.PortalSubmit
  alias ZeroCoupledWeb.Paradigms.Instance

  # outputs this instance shows itself; every other port its feature declares is announced
  @lands_only [:form, :approved]

  @doc "The ports this instance announces, as `{name, port, payload}`."
  def announces, do: Keyword.keys(PortalSubmit.ports().out) -- @lands_only

  def update(%{review: summary}, s), do: {:ok, step(s, &PortalSubmit.review(&1, summary))}
  def update(assigns, s), do: {:ok, s |> assign(assigns) |> ensure_started() |> follow_url()}

  defp ensure_started(%{assigns: %{state: _}} = s), do: s

  defp ensure_started(%{assigns: a} = s) do
    flow =
      PortalSubmit.new(
        flow: a.flow,
        start: a.start,
        url_edges: a.url_edges,
        messages: a.messages
      )

    assign(s,
      state: flow,
      step: a.start,
      po_form: to_form(PortalSubmit.po_form(flow)),
      po: nil,
      order_id: nil,
      seen_step: nil
    )
  end

  defp follow_url(%{assigns: %{requested_step: step, seen_step: step}} = s), do: s

  defp follow_url(%{assigns: %{requested_step: step}} = s),
    do: s |> assign(seen_step: step) |> step(&PortalSubmit.goto(&1, step))

  def handle_event("validate_po", %{"po" => p}, s),
    do: {:noreply, step(s, &PortalSubmit.validate(&1, p))}

  def handle_event("submit_order", %{"po" => p}, s),
    do: {:noreply, step(s, &PortalSubmit.submit(&1, p))}

  def handle_event("edit_lines", _, s), do: {:noreply, step(s, &PortalSubmit.edit_lines(&1, nil))}

  defp step(s, fun), do: Instance.step(s, fun, &land/2)

  defp land(s, {:step, step} = out),
    do: s |> assign(step: step) |> Instance.announce(:submit, out)

  defp land(s, {:form, changeset}), do: assign(s, po_form: to_form(changeset, action: :validate))

  defp land(s, {:approved, po}),
    do: s |> assign(po: po) |> step(&PortalSubmit.complete(&1, place_order(s.assigns)))

  defp land(s, {:reference, id} = out),
    do: s |> assign(order_id: id) |> Instance.announce(:submit, out)

  defp land(s, out), do: Instance.announce(s, :submit, out)

  defp place_order(%{place_order: place_order, cart_id: cart_id}) do
    {:ok, order} = PlaceOrder.run(place_order, cart_id)
    order.id
  end

  def render(%{step: :review} = assigns) do
    ~H"""
    <div class="space-y-4 max-w-lg">
      <.order_summary summary={@summary} t={@t.summary} />
      <.simple_form
        for={@po_form}
        phx-change="validate_po"
        phx-submit="submit_order"
        phx-target={@myself}
      >
        <.input field={@po_form[:number]} label={@t.po_number} placeholder={@t.po_placeholder} />
        <.input field={@po_form[:notes]} label={@t.notes} />
        <:actions>
          <button
            type="button"
            phx-click="edit_lines"
            phx-target={@myself}
            class="text-sm text-zinc-500 underline"
          >
            {@t.back}
          </button>
          <.button phx-disable-with={@t.submitting}>{@t.submit} · {@summary.total}</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def render(%{step: :submitted} = assigns) do
    ~H"""
    <div class="py-10 space-y-2">
      <h2 class="text-2xl font-semibold">{@t.submitted}</h2>
      <p class="text-zinc-600">
        {@t.reference} <span class="font-mono">#{@order_id}</span> · {@po.number}
      </p>
      <p class="text-zinc-500 text-sm">
        {@t.total} {@summary.total} ({@summary.item_count} {@t.items})
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div></div>
    """
  end
end
