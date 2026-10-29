defmodule GoodDeal.Catalog.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :description, :string
    field :amount, :integer
    field :stock, :integer, default: 0
    field :thumbnail, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :description, :amount, :stock, :thumbnail])
    |> validate_required([:name, :amount])
    |> validate_number(:amount, greater_than_or_equal_to: 0)
    |> validate_number(:stock, greater_than_or_equal_to: 0)
  end
end
