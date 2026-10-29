# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     GoodDeal.Repo.insert!(%GoodDeal.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias GoodDeal.Catalog

for attrs <- [
      %{name: "Coffee Mug", description: "Stoneware, 350 ml.", amount: 1299, stock: 40},
      %{name: "French Press", description: "Borosilicate glass, 1 l.", amount: 3499, stock: 12},
      %{name: "Burr Grinder", description: "Conical burrs, 15 settings.", amount: 8999, stock: 4},
      %{name: "Pour-over Kettle", description: "Gooseneck spout, 0.9 l.", amount: 4599, stock: 8},
      %{name: "Espresso Beans", description: "1 kg, medium roast.", amount: 2199, stock: 0}
    ] do
  {:ok, _} =
    attrs
    |> Map.put(:thumbnail, "https://placehold.co/96x96?text=#{URI.encode(attrs.name)}")
    |> Catalog.create_product()
end
