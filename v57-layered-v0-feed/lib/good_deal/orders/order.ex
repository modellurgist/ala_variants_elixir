defmodule GoodDeal.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  schema "orders" do
    field :source, Ecto.Enum, values: [:storefront, :portal]
    field :po_number, :string
    field :address, :map
    field :subtotal, :integer
    field :discount, :integer
    field :gift_wrap, :integer
    field :shipping, :integer
    field :total, :integer

    belongs_to :cart, GoodDeal.ShoppingCart.Cart
    has_many :line_items, GoodDeal.Orders.LineItem

    timestamps(type: :utc_datetime)
  end

  # A storefront order ships to an address; a portal order is billed to a PO number.
  @required_by_source %{storefront: [:address], portal: [:po_number]}

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
    |> validate_required([:source, :subtotal, :discount, :gift_wrap, :shipping, :total])
    |> validate_source_fields()
  end

  defp validate_source_fields(changeset) do
    validate_required(changeset, Map.get(@required_by_source, get_field(changeset, :source), []))
  end
end
