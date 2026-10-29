defmodule GoodDeal.Foundation.Schemas.CartTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Foundation.Schemas.Cart

  describe "changeset/2" do
    test "valid with open status" do
      changeset = Cart.changeset(%Cart{}, %{status: :open})
      assert changeset.valid?
    end

    test "valid with completed status" do
      changeset = Cart.changeset(%Cart{}, %{status: :completed})
      assert changeset.valid?
    end

    test "valid with abandoned status" do
      changeset = Cart.changeset(%Cart{}, %{status: :abandoned})
      assert changeset.valid?
    end

    test "invalid when status is missing" do
      changeset = Cart.changeset(%Cart{}, %{})
      refute changeset.valid?
    end
  end
end
