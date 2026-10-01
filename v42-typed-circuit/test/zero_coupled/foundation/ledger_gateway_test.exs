defmodule ZeroCoupled.Foundation.LedgerGatewayTest do
  use ExUnit.Case, async: true

  alias ZeroCoupled.Foundation.LedgerGateway

  test "create_checkout_session/3 returns the success url to advance to" do
    urls = %{success_url: "/cart/success", cancel_url: "/cart"}
    assert {:ok, "/cart/success"} = LedgerGateway.create_checkout_session([], %{}, urls)
  end
end
