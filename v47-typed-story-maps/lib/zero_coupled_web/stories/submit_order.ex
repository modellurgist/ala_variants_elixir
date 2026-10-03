defmodule ZeroCoupledWeb.Stories.SubmitOrder do
  @moduledoc """
  A business buyer reviews the order, gives a purchase order number, and submits it. Its part is the
  submission's step machine; its configured `PlaceOrder` places the order; its view is the review and
  done steps.
  """
  use ZeroCoupledWeb, :html
  @behaviour ZeroCoupledWeb.Paradigms.Binder
  import ZeroCoupled.Catalog.Panes, only: [only_on: 1]
  import ZeroCoupled.Catalog.Rows, only: [order_summary: 1]

  alias ZeroCoupled.State.PortalSubmit
  alias ZeroCoupledWeb.Paradigms.Binder

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

  @doc "Config: `flow`, the options of its step machine (see `ZeroCoupled.State.PortalSubmit`), and `place_order`."
  def new(opts),
    do:
      Binder.story(
        __MODULE__,
        %{flow: PortalSubmit.new(opts[:flow])},
        bindings(opts[:place_order]),
        form: nil,
        summary: nil,
        po: nil,
        order_id: nil
      )

  # {source, port} → where it goes in this story; {:in, port} is the story's own input
  def bindings(place_order) do
    %{
      {:in, :mounted} => [{:input, :flow, &PortalSubmit.show_form/2}],
      {:in, :review} => [{:input, :flow, &PortalSubmit.review/2}],
      {:in, :summary} => [{:show, :summary}],
      {:in, :goto} => [{:input, :flow, &PortalSubmit.goto/2}],
      {:flow, :step} => [{:patch, @step_paths}, {:out, :step}],
      {:flow, :form} => [{:form, :form}],
      {:flow, :blocked} => [{:flash_for, :error, @blocked}],
      {:flow, :approved} => [
        {:show, :po},
        {:via, place_order, [{:input, :flow, &PortalSubmit.complete/2}]}
      ],
      {:flow, :reference} => [{:show, :order_id}, {:flash, :info, "Order submitted"}]
    }
  end

  def event(s, me, "edit_lines", _),
    do: Binder.run(s, me, :flow, &PortalSubmit.edit_lines(&1, nil))

  def event(s, me, "validate_po", %{"po" => params}),
    do: Binder.run(s, me, :flow, &PortalSubmit.validate(&1, params))

  def event(s, me, "submit_order", %{"po" => params}),
    do: Binder.run(s, me, :flow, &PortalSubmit.submit(&1, params))

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
