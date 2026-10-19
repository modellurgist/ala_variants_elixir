defmodule GoodDeal.ShoppingCart.Address do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :line1, :string
    field :city, :string
    field :postal_code, :string
  end

  @doc false
  def changeset(address, attrs) do
    address
    |> cast(attrs, [:name, :line1, :city, :postal_code])
    |> validate_required([:name, :line1, :city, :postal_code])
    |> validate_length(:postal_code, min: 3, max: 10)
  end
end
