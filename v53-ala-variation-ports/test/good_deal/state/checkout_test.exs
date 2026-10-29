defmodule GoodDeal.State.CheckoutTest do
  use ExUnit.Case, async: true
  alias GoodDeal.State.Checkout

  @flow [
    {:address, :submit_address, :payment},
    {:payment, :edit_address, :address},
    {:payment, :pay, :processing}
  ]
  @address %{"name" => "Ada", "line1" => "1 Ave", "city" => "London", "postal_code" => "12345"}

  defp checkout,
    do:
      Checkout.new(
        flow: @flow,
        start: :address,
        url_edges: [{:payment, :address}],
        stock_levels: fn _ -> %{} end,
        line_items: GoodDeal.Domain.BuildLineItems.new(currency: "usd"),
        messages: %{postal_code: "must be 4–10 digits"}
      )

  test "an empty cart cannot start" do
    assert Checkout.start(checkout(), %{empty?: true}) == {:blocked, :empty}
    assert {:ok, %{step: :address}} = Checkout.start(checkout(), %{empty?: false})
  end

  test "an accepted address moves along the flow; a rejected one answers the form" do
    assert {:error, %Ecto.Changeset{valid?: false}} =
             Checkout.submit_address(checkout(), %{"name" => ""})

    assert {:ok, %{step: :payment, address: %{name: "Ada"}} = c} =
             Checkout.submit_address(checkout(), @address)

    assert %{step: :address} = Checkout.edit_address(c)
  end

  test "the URL may only jump along declared edges" do
    {:ok, c} = Checkout.submit_address(checkout(), @address)
    assert %{step: :address} = Checkout.goto(c, :address)
    assert %{step: :address} = Checkout.goto(checkout(), :payment)
  end

  test "payment outcomes" do
    {:ok, c} = Checkout.submit_address(checkout(), @address)
    assert %{step: :error} = c = Checkout.failed(c)
    assert %{step: :complete} = Checkout.succeeded(c)
  end

  defp line(id, product_id, quantity),
    do: %{
      id: id,
      quantity: quantity,
      product: %{id: product_id, name: "W", description: "", thumbnail: "", amount: 1000}
    }

  defp at_payment(levels) do
    {:ok, c} = Checkout.submit_address(%{checkout() | stock_levels: fn _ -> levels end}, @address)
    c
  end

  test "paying takes the cart's id and lines: empty or out of stock blocks, otherwise the lines are charged" do
    assert Checkout.pay(at_payment(%{}), {42, []}) == {:blocked, :empty}
    assert Checkout.pay(at_payment(%{7 => 1}), {42, [line(1, 7, 2)]}) == {:blocked, :out_of_stock}

    assert {:ok, %{step: :processing}, {[%{unit_amount: 1000, quantity: 2}], 42}} =
             Checkout.pay(at_payment(%{7 => 5}), {42, [line(1, 7, 2)]})
  end
end
