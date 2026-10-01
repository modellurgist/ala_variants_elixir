defmodule ZeroCoupledWeb.PortalLive.PortalView do
  @moduledoc "The portal's screens: lines and catalog, then the PO review, then the confirmation."
  use ZeroCoupledWeb, :html
  import ZeroCoupled.Catalog.Rows
  import ZeroCoupled.Catalog.{Panes, Parts}

  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto px-6">
      <h1 class="text-4xl pb-2 font-semibold">Bulk Order Portal</h1>
      <.milestones step={@step} milestones={@milestones} />
      <.only_on current={@step} name={:lines}>
        <div class="space-y-8">
          <.notice
            shown={@undo_pending}
            text={@texts.undo.text}
            action={@texts.undo.undo}
            event="undo_remove"
          />
          <section>
            <h2 class="text-lg font-semibold pb-2">{@texts.order.heading}</h2>
            <.stream_list :let={{dom_id, row}} id="order_lines" stream={@streams.order_lines}>
              <.order_line_row
                id={dom_id}
                row={row}
                on_quantity="set_line_quantity"
                on_remove="remove_line"
                t={@texts.order.row}
              />
            </.stream_list>
            <.none count={@summary.item_count} text={@texts.order.empty} />
            <.order_summary summary={@summary} t={@texts.order.summary} />
            <.primary_button event="go_review" disabled={@summary.empty?}>
              {@texts.order.review} · {@summary.total}
            </.primary_button>
          </section>
          <section>
            <h2 class="text-lg font-semibold pb-2">{@texts.catalog.heading}</h2>
            <.stream_list :let={{dom_id, row}} id="portal_products" stream={@streams.portal_products}>
              <.catalog_row
                id={dom_id}
                row={row}
                on_add="add_to_order"
                t={@texts.catalog.row}
              />
            </.stream_list>
          </section>
        </div>
      </.only_on>
      <.only_on current={@step} name={:review}>
        <div class="space-y-4 max-w-lg">
          <.order_summary summary={@summary} t={@texts.order.summary} />
          <.simple_form for={@po_form} phx-change="validate_po" phx-submit="submit_order">
            <.input
              field={@po_form[:number]}
              label={@texts.submit.po_number}
              placeholder={@texts.submit.po_placeholder}
            />
            <.input field={@po_form[:notes]} label={@texts.submit.notes} />
            <:actions>
              <button type="button" phx-click="edit_lines" class="text-sm text-zinc-500 underline">
                {@texts.submit.back}
              </button>
              <.button phx-disable-with={@texts.submit.submitting}>
                {@texts.submit.submit} · {@summary.total}
              </.button>
            </:actions>
          </.simple_form>
        </div>
      </.only_on>
      <.only_on current={@step} name={:submitted}>
        <div class="py-10 space-y-2">
          <h2 class="text-2xl font-semibold">{@texts.submit.submitted}</h2>
          <p class="text-zinc-600">
            {@texts.submit.reference} <span class="font-mono">#{@order_id}</span> · {@po.number}
          </p>
          <p class="text-zinc-500 text-sm">
            {@texts.submit.total} {@summary.total} ({@summary.item_count} {@texts.submit.items})
          </p>
        </div>
      </.only_on>
    </div>
    """
  end
end
