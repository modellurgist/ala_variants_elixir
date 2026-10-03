defmodule GoodDealWeb.Stories.SubmitOrder do
  @moduledoc """
  A business buyer reviews the order, gives a purchase order number, and submits it. Its part is the
  submission's step machine; its instance places the order; its view is the review and done steps.
  Ports: `mounted`, `review` with the order's summary, the `summary` as it changes, and `goto` a step
  the URL names.
  """
  use GoodDealWeb, :html
  @behaviour GoodDealWeb.Paradigms.Story
  import Phoenix.LiveView, only: [put_flash: 3]
  import GoodDeal.Components.Panes, only: [only_on: 1]
  import GoodDeal.Components.Rows, only: [order_summary: 1]

  alias GoodDeal.Domain.PlaceOrder
  alias GoodDeal.State.PortalSubmit
  alias GoodDealWeb.Paradigms.{Sinks, Story}

  @step_paths %{lines: "/portal", review: "/portal/review", submitted: "/portal/submitted"}
  @blocked %{empty: "Your order is empty"}

  def parts, do: %{flow: PortalSubmit}
  def streams, do: []
  def events, do: ~w(edit_lines validate_po submit_order)

  def ports,
    do: %{
      in: [mounted: :event, review: :summary, summary: :summary, goto: :step],
      out: [step: :step]
    }

  @doc "Config: `flow`, the options of its step machine (see `GoodDeal.State.PortalSubmit`), and `place_order`."
  def new(opts),
    do:
      Story.new(__MODULE__, %{flow: PortalSubmit.new(opts[:flow])},
        instances: %{place_order: opts[:place_order]},
        view: [form: nil, summary: nil, po: nil, order_id: nil]
      )

  def input(s, me, :mounted, _), do: Story.run(s, me, :flow, &PortalSubmit.show_form(&1, nil))

  def input(s, me, :review, summary),
    do: Story.run(s, me, :flow, &PortalSubmit.review(&1, summary))

  def input(s, me, :summary, summary), do: Story.show(s, me, :summary, summary)
  def input(s, me, :goto, step), do: Story.run(s, me, :flow, &PortalSubmit.goto(&1, step))

  def event(s, me, "edit_lines", _),
    do: Story.run(s, me, :flow, &PortalSubmit.edit_lines(&1, nil))

  def event(s, me, "validate_po", %{"po" => params}),
    do: Story.run(s, me, :flow, &PortalSubmit.validate(&1, params))

  def event(s, me, "submit_order", %{"po" => params}),
    do: Story.run(s, me, :flow, &PortalSubmit.submit(&1, params))

  # {part, port} → where it wires inside this story, or out of it
  def wire(s, me, :flow, {:step, step}),
    do: s |> Sinks.patch(@step_paths, step) |> Story.send_out(me, :step, step)

  def wire(s, me, :flow, {:form, changeset}),
    do: Story.show(s, me, :form, to_form(changeset, action: :validate))

  def wire(s, _me, :flow, {:blocked, reason}), do: put_flash(s, :error, @blocked[reason])

  def wire(s, me, :flow, {:approved, po}),
    do:
      s
      |> Story.show(me, :po, po)
      |> Story.feed(me, :flow, &PortalSubmit.complete/2, {:place_order, &PlaceOrder.place/2}, po)

  def wire(s, me, :flow, {:reference, order_id}),
    do: s |> Story.show(me, :order_id, order_id) |> put_flash(:info, "Order submitted")

  attr :story, :map, required: true
  attr :step, :atom, required: true
  attr :t, :map, required: true, doc: "the submission's texts, and the summary's, from the page"

  def view(assigns) do
    ~H"""
    <.only_on current={@step} name={:review}>
      <div class="space-y-4 max-w-lg">
        <.order_summary summary={@story.view.summary} t={@t.summary} />
        <.simple_form for={@story.view.form} phx-change="validate_po" phx-submit="submit_order">
          <.input
            field={@story.view.form[:number]}
            label={@t.po_number}
            placeholder={@t.po_placeholder}
          />
          <.input field={@story.view.form[:notes]} label={@t.notes} />
          <:actions>
            <button type="button" phx-click="edit_lines" class="text-sm text-zinc-500 underline">
              {@t.back}
            </button>
            <.button phx-disable-with={@t.submitting}>
              {@t.submit} · {@story.view.summary.total}
            </.button>
          </:actions>
        </.simple_form>
      </div>
    </.only_on>
    <.only_on current={@step} name={:submitted}>
      <div class="py-10 space-y-2">
        <h2 class="text-2xl font-semibold">{@t.submitted}</h2>
        <p class="text-zinc-600">
          {@t.reference} <span class="font-mono">#{@story.view.order_id}</span>
          · {@story.view.po.number}
        </p>
        <p class="text-zinc-500 text-sm">
          {@t.total} {@story.view.summary.total} ({@story.view.summary.item_count} {@t.items})
        </p>
      </div>
    </.only_on>
    """
  end
end
