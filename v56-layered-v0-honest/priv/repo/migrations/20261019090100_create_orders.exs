defmodule GoodDeal.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :cart_id, references(:carts, on_delete: :nilify_all)
      add :source, :string, null: false
      add :po_number, :string
      add :address, :map
      add :subtotal, :integer, null: false
      add :discount, :integer, null: false, default: 0
      add :gift_wrap, :integer, null: false, default: 0
      add :shipping, :integer, null: false, default: 0
      add :total, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:orders, [:cart_id])

    create table(:order_line_items) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :nilify_all)
      add :name, :string, null: false
      add :unit_price, :integer, null: false
      add :quantity, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:order_line_items, [:order_id])
    create index(:order_line_items, [:product_id])
  end
end
