defmodule GoodDeal.Orders.PurchaseOrder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :number, :string
  end

  @doc false
  def changeset(purchase_order, attrs) do
    purchase_order
    |> cast(attrs, [:number])
    |> validate_required([:number])
    |> validate_format(:number, ~r/^PO-\d{4,}$/, message: "must look like PO-1234")
  end
end
