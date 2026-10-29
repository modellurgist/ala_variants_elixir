defmodule GoodDeal.Repo.Migrations.AddRemovedAtToCartItems do
  use Ecto.Migration

  def change do
    alter table(:cart_items) do
      add :removed_at, :utc_datetime_usec
    end
  end
end
