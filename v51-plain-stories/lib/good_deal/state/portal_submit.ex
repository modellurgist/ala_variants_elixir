defmodule GoodDeal.State.PortalSubmit do
  @moduledoc """
  Submitting a bulk order: a step machine over a flow table the page supplies, plus the purchase
  order the buyer enters. Ports out: `:step`, `:form` (the PO changeset), `:blocked` (`:empty`),
  `:approved` (a validated PO, ready to be placed somewhere else), `:reference` (the placed order's id).
  """
  alias GoodDeal.Paradigms.Transitions

  defmodule PO do
    @moduledoc "A purchase order number, validated as an embedded schema."
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :number, :string
      field :notes, :string
    end

    def changeset(po, params, messages) do
      po
      |> cast(params, [:number, :notes])
      |> validate_required([:number])
      |> validate_format(:number, ~r/^PO-\d{4,}$/, message: messages.number)
    end
  end

  defstruct flow: nil, po: nil, order_id: nil, messages: %{}

  def ports,
    do: %{
      in: [
        review: :summary,
        show_form: :event,
        edit_lines: :event,
        validate: :params,
        submit: :params,
        complete: :order_id,
        goto: :step
      ],
      out: [step: :step, form: :changeset, approved: :po, blocked: :reason, reference: :order_id]
    }

  def new(opts) do
    %__MODULE__{
      flow:
        Transitions.new(
          Keyword.fetch!(opts, :flow),
          Keyword.fetch!(opts, :start),
          Keyword.get(opts, :url_edges, [])
        ),
      messages: Keyword.fetch!(opts, :messages),
      po: %PO{}
    }
  end

  def po_form(%__MODULE__{po: po} = s, params \\ %{}), do: PO.changeset(po, params, s.messages)
  def po_number(%__MODULE__{po: po}), do: po.number

  @doc "Show the purchase-order form as it stands."
  def show_form(%__MODULE__{} = s, _), do: {s, [form: po_form(s)]}

  def review(%__MODULE__{} = s, %{empty?: true}), do: {s, [blocked: :empty]}
  def review(%__MODULE__{} = s, _summary), do: advance(s, :go_review)

  def edit_lines(%__MODULE__{} = s, _), do: advance(s, :edit_lines)

  def validate(%__MODULE__{} = s, params), do: {s, [form: po_form(s, params)]}

  def submit(%__MODULE__{} = s, params) do
    case Ecto.Changeset.apply_action(po_form(s, params), :insert) do
      {:ok, po} -> {%{s | po: po}, [approved: po]}
      {:error, changeset} -> {s, [form: changeset]}
    end
  end

  @doc "The order was placed: finish."
  def complete(%__MODULE__{} = s, order_id) do
    {s, outs} = advance(%{s | order_id: order_id}, :submit_order)
    {s, outs ++ [reference: order_id]}
  end

  def goto(%__MODULE__{} = s, step), do: on_flow(s, Transitions.jump(s.flow, step))

  defp advance(s, event), do: on_flow(s, Transitions.fire(s.flow, event))

  defp on_flow(s, {:moved, flow}), do: {%{s | flow: flow}, [step: flow.step]}
  defp on_flow(s, {:stayed, _}), do: {s, []}
end
