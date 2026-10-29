defmodule GoodDeal.State.PortalSubmit do
  @moduledoc """
  Submitting a bulk order: a step machine over a flow table the page supplies, plus the purchase
  order the buyer enters and the placed order's id. Each move answers the flow in its new step; a
  move that can't happen answers why: a changeset to show, or `{:blocked, :empty}`. A valid PO is
  answered for something else to place.
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

  defstruct step: nil, flow: [], url_edges: [], po: nil, order_id: nil, messages: %{}

  def new(opts) do
    %__MODULE__{
      flow: Keyword.fetch!(opts, :flow),
      step: Keyword.fetch!(opts, :start),
      url_edges: Keyword.get(opts, :url_edges, []),
      messages: Keyword.fetch!(opts, :messages),
      po: %PO{}
    }
  end

  @doc "The purchase-order form as it stands, or with `params` typed into it."
  def po_form(%__MODULE__{po: po} = s, params \\ %{}), do: PO.changeset(po, params, s.messages)

  def review(%__MODULE__{}, %{empty?: true}), do: {:blocked, :empty}
  def review(%__MODULE__{} = s, _summary), do: {:ok, move(s, :go_review)}

  def edit_lines(%__MODULE__{} = s), do: move(s, :edit_lines)

  @doc "`{:ok, flow, po}` for a valid purchase order, ready to be placed; `{:error, changeset}` otherwise."
  def submit(%__MODULE__{} = s, params) do
    case Ecto.Changeset.apply_action(po_form(s, params), :insert) do
      {:ok, po} -> {:ok, %{s | po: po}, po}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "The order was placed: finish."
  def complete(%__MODULE__{} = s, order_id), do: move(%{s | order_id: order_id}, :submit_order)

  def goto(%__MODULE__{} = s, step), do: %{s | step: Transitions.jump(s.url_edges, s.step, step)}

  defp move(s, event), do: %{s | step: Transitions.next(s.flow, s.step, event)}
end
