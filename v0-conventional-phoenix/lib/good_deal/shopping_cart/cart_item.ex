defmodule GoodDeal.ShoppingCart.CartItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "cart_items" do
    field :quantity, :integer, default: 1
    field :gift_wrap, :boolean, default: false
    field :saved_for_later, :boolean, default: false

    belongs_to :cart, GoodDeal.ShoppingCart.Cart
    belongs_to :product, GoodDeal.Catalog.Product

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cart_item, attrs) do
    cart_item
    |> cast(attrs, [:quantity, :gift_wrap, :saved_for_later])
    |> validate_required([:quantity])
    |> validate_number(:quantity, greater_than_or_equal_to: 1)
  end
end
