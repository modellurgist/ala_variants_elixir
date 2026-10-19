defmodule GoodDeal.Foundation.Schemas.CartItem do
  use Ecto.Schema
  import Ecto.Changeset

  alias GoodDeal.Foundation.Schemas.Product

  schema "cart_items" do
    field :quantity, :integer
    field :cart_id, :id
    field :removed_at, :utc_datetime_usec
    field :saved_at, :utc_datetime_usec
    belongs_to :product, Product

    timestamps()
  end

  def changeset(cart_item, attrs) do
    cart_item
    |> cast(attrs, [:quantity])
    |> validate_required([:quantity])
  end
end
