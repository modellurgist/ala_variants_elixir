defmodule GoodDeal.Orders.PurchaseOrder do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :number, :string
  end

  @doc false
  def changeset(purchase_order, attrs, %{format: format, message: message}) do
    purchase_order
    |> cast(attrs, [:number])
    |> validate_required([:number])
    |> validate_format(:number, format, message: message)
  end
end
