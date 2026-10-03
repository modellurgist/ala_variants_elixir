defmodule GoodDeal.Foundation.Schemas.Order do
  use Ecto.Schema
  import Ecto.Changeset

  schema "orders" do
    field :cart_id, :id

    timestamps()
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [])
    |> validate_required([])
  end
end
