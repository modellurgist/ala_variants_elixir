defmodule GoodDeal.Foundation.LedgerGatewayTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Foundation.LedgerGateway

  test "charge/3 settles a positive amount and returns a reference" do
    assert {:ok, "chg_" <> _rest} = LedgerGateway.charge(1500, "usd", %{cart_id: "1"})
  end

  test "charge/3 rejects a non-positive amount" do
    assert {:error, :invalid_charge} = LedgerGateway.charge(0, "usd", %{})
    assert {:error, :invalid_charge} = LedgerGateway.charge(-100, "usd", %{})
  end

  test "charge/3 returns distinct references per call" do
    {:ok, a} = LedgerGateway.charge(1000, "usd", %{})
    {:ok, b} = LedgerGateway.charge(1000, "usd", %{})
    refute a == b
  end
end
