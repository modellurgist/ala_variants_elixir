# The portal's order-submission feature: PO capture + the bulk-order flow
# slot. The wizard skeleton (steps, edges, URLs) lives in the portal
# manifest's flows/0 channel; this feature consults the generated
# `ZeroCoupled.Flows` table for its own flow — the same shape as
# CheckoutFlow, which the D6 census records as a candidate for a shared
# "flow slot" abstraction at consumer three.

defmodule ZeroCoupled.Features.PortalSubmit do
  @moduledoc """
  The bulk-order submission flow: `:lines → :review → :submitted`, with a
  purchase-order number validated by an embedded schema (pure, in-memory
  changeset — Ecto as platform, not peer).
  """

  defmodule PO do
    @moduledoc "Embedded schema for the purchase-order sub-form."
    use Ecto.Schema
    import Ecto.Changeset

    @type t :: %__MODULE__{}

    @primary_key false
    embedded_schema do
      field :number, :string
      field :notes, :string
    end

    @spec changeset(t(), map()) :: Ecto.Changeset.t()
    def changeset(po, params) do
      po
      |> cast(params, [:number, :notes])
      |> validate_required([:number])
      |> validate_format(:number, ~r/^PO-\d{4,}$/, message: "must look like PO-1234")
    end
  end

  @type step :: :lines | :review | :submitted
  @type t :: %__MODULE__{step: step(), po: PO.t() | nil, order_id: term()}

  defstruct step: :lines, po: nil, order_id: nil

  @spec init(keyword()) :: t()
  def init(_opts), do: %__MODULE__{step: ZeroCoupled.Flows.initial(:bulk_order)}

  @doc "Changeset for rendering / live-validating the PO form."
  @spec po_changeset(t(), map()) :: Ecto.Changeset.t()
  def po_changeset(%__MODULE__{po: po}, params \\ %{}), do: PO.changeset(po || %PO{}, params)

  @doc "L5 presentation port (`render: :render_data` → `@flow`)."
  @spec render_data(t()) :: map()
  def render_data(%__MODULE__{} = flow) do
    %{step: flow.step, po_number: flow.po && flow.po.number, order_id: flow.order_id}
  end

  @doc "The declared to-step for a UI event from the current step, off the flow table."
  @spec advance(t(), atom()) :: atom()
  def advance(%__MODULE__{step: step}, event), do: ZeroCoupled.Flows.advance(:bulk_order, step, event)

  @spec goto(t(), atom()) :: t()
  def goto(%__MODULE__{} = flow, :no_transition), do: flow
  def goto(%__MODULE__{} = flow, step), do: %{flow | step: step}

  @doc """
  URL-navigation policy: the browser may only move back to the lines step
  along the `:edit_lines` edge; a submitted order never navigates back.
  """
  @spec can_goto?(t(), atom()) :: boolean()
  def can_goto?(%__MODULE__{} = flow, step), do: advance(flow, :edit_lines) == step
end

defmodule ZeroCoupled.Features.PortalSubmit.Intents do
  @moduledoc false
  use ZeroCoupled.Feature.Intents, slot: :flow

  alias ZeroCoupled.{Cart, Effects}
  alias ZeroCoupled.Features.PortalSubmit

  # ── Intents ──────────────────────────────────────────────────────────

  intent :go_review

  def go_review(session, _args) do
    if Cart.empty?(session.order) do
      {session, [Effects.flash(:error, "Your order is empty")]}
    else
      step = PortalSubmit.advance(session.flow, :go_review)

      {put_slot(session, PortalSubmit.goto(session.flow, step)),
       [Effects.patch_flow(:bulk_order, step)]}
    end
  end

  intent :edit_lines

  def edit_lines(session, _args) do
    step = PortalSubmit.advance(session.flow, :edit_lines)

    {put_slot(session, PortalSubmit.goto(session.flow, step)),
     [Effects.patch_flow(:bulk_order, step)]}
  end

  @doc "Live-validate the PO form (no state transition). Irregular helper."
  def change_po(session, params), do: PortalSubmit.po_changeset(session.flow, params)

  @doc "Irregular: validate the PO before the shell performs the order I/O."
  @spec validate_po(map(), map()) :: {:ok, PortalSubmit.PO.t()} | {:error, Ecto.Changeset.t()}
  def validate_po(session, params) do
    session.flow
    |> PortalSubmit.po_changeset(params)
    |> Ecto.Changeset.apply_action(:insert)
  end

  @doc "Irregular: the order was persisted (shell I/O) — complete the flow."
  def complete_submit(session, po, order_id) do
    step = PortalSubmit.advance(session.flow, :submit_order)
    flow = %{PortalSubmit.goto(session.flow, step) | po: po, order_id: order_id}

    {put_slot(session, flow),
     [Effects.patch_flow(:bulk_order, step), Effects.flash(:info, "Order submitted")]}
  end

  @doc "Irregular (from handle_params): the URL asked for a step."
  def goto_step(session, step) do
    if PortalSubmit.can_goto?(session.flow, step),
      do: {put_slot(session, PortalSubmit.goto(session.flow, step)), []},
      else: {session, []}
  end
end
