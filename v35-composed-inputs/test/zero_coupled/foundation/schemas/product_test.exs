defmodule ZeroCoupled.Foundation.Schemas.ProductTest do
  use ExUnit.Case, async: true

  alias ZeroCoupled.Foundation.Schemas.Product

  describe "changeset/2" do
    test "valid with all required fields" do
      changeset =
        Product.changeset(%Product{}, %{
          name: "Widget",
          description: "A fine widget",
          amount: 999,
          stock: 10,
          thumbnail: "widget.png"
        })

      assert changeset.valid?
    end

    test "invalid when name is missing" do
      changeset = Product.changeset(%Product{}, %{description: "x", amount: 1, stock: 1, thumbnail: "x"})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when amount is missing" do
      changeset = Product.changeset(%Product{}, %{name: "x", description: "x", stock: 1, thumbnail: "x"})
      refute changeset.valid?
      assert %{amount: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when all fields are nil" do
      changeset = Product.changeset(%Product{}, %{})
      refute changeset.valid?
      errors = errors_on(changeset)
      assert errors[:name]
      assert errors[:description]
      assert errors[:amount]
      assert errors[:stock]
      assert errors[:thumbnail]
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
