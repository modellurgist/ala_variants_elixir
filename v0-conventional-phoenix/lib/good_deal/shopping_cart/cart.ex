defmodule GoodDeal.ShoppingCart.Cart do
  use Ecto.Schema
  import Ecto.Changeset

  alias GoodDeal.ShoppingCart.{Address, CartItem}

  schema "carts" do
    field :status, Ecto.Enum, values: [:open, :completed, :abandoned], default: :open
    field :promo_code, :string
    field :shipping_method, :string, default: "standard"
    embeds_one :address, Address, on_replace: :delete

    has_many :items, CartItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cart, attrs) do
    cart
    |> cast(attrs, [:status, :promo_code, :shipping_method])
    |> validate_required([:status, :shipping_method])
  end
end
