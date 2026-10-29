defmodule GoodDeal.Repo.Migrations.CreateCarts do
  use Ecto.Migration

  def change do
    create table(:carts) do
      add :status, :string, null: false, default: "open"
      add :promo_code, :string
      add :shipping_method, :string, null: false, default: "standard"
      add :address, :map

      timestamps(type: :utc_datetime)
    end

    create table(:cart_items) do
      add :cart_id, references(:carts, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false
      add :quantity, :integer, null: false, default: 1
      add :gift_wrap, :boolean, null: false, default: false
      add :saved_for_later, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cart_items, [:cart_id, :product_id])
    create index(:cart_items, [:product_id])

    create table(:wishlist_items) do
      add :cart_id, references(:carts, on_delete: :delete_all), null: false
      add :product_id, references(:products, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:wishlist_items, [:cart_id, :product_id])
    create index(:wishlist_items, [:product_id])
  end
end
