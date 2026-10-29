defmodule GoodDeal.Orders.LineItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "order_line_items" do
    field :name, :string
    field :unit_price, :integer
    field :quantity, :integer

    belongs_to :order, GoodDeal.Orders.Order
    belongs_to :product, GoodDeal.Catalog.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(line_item, attrs) do
    line_item
    |> cast(attrs, [:product_id, :name, :unit_price, :quantity])
    |> validate_required([:name, :unit_price, :quantity])
  end
end
