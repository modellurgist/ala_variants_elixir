defmodule GoodDeal.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  schema "orders" do
    field :source, Ecto.Enum, values: [:storefront, :portal]
    field :po_number, :string
    field :address, :map
    field :subtotal, :integer
    field :discount, :integer, default: 0
    field :gift_wrap, :integer, default: 0
    field :shipping, :integer, default: 0
    field :total, :integer

    belongs_to :cart, GoodDeal.ShoppingCart.Cart
    has_many :line_items, GoodDeal.Orders.LineItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :source,
      :po_number,
      :address,
      :subtotal,
      :discount,
      :gift_wrap,
      :shipping,
      :total
    ])
    |> cast_assoc(:line_items, required: true)
    |> validate_required([:source, :subtotal, :total])
  end
end
