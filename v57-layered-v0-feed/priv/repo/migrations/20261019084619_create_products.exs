defmodule GoodDeal.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, null: false
      add :description, :text
      add :amount, :integer, null: false
      add :stock, :integer, null: false, default: 0
      add :thumbnail, :string

      timestamps(type: :utc_datetime)
    end
  end
end
