defmodule GoodDeal.Repo.Migrations.AddSavedAtToCartItems do
  use Ecto.Migration

  def change do
    alter table(:cart_items) do
      add :saved_at, :utc_datetime_usec
    end
  end
end
