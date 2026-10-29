defmodule GoodDeal.ShoppingCart.WishlistItem do
  use Ecto.Schema

  schema "wishlist_items" do
    belongs_to :cart, GoodDeal.ShoppingCart.Cart
    belongs_to :product, GoodDeal.Catalog.Product

    timestamps(type: :utc_datetime)
  end
end
