defmodule ZeroCoupled.State.CheckoutTest do
  use ExUnit.Case, async: true
  alias ZeroCoupled.State.Checkout

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
        line_items: ZeroCoupled.Domain.BuildLineItems.new(currency: "usd"),
        messages: %{postal_code: "must be 4–10 digits"}
      )

  test "an empty cart cannot start" do
    assert {_, [blocked: :empty]} = Checkout.start(checkout(), %{empty?: true})

    assert {_, [step: :address, form: %Ecto.Changeset{}]} =
             Checkout.start(checkout(), %{empty?: false})
  end

  test "an accepted address moves along the flow; a rejected one shows the form" do
    assert {_, [form: %Ecto.Changeset{valid?: false}]} =
             Checkout.submit_address(checkout(), %{"name" => ""})

    assert {c, [address: %{name: "Ada"}, step: :payment]} =
             Checkout.submit_address(checkout(), @address)

    assert {_, [step: :address]} = Checkout.edit_address(c, nil)
  end

  test "the URL may only jump along declared edges" do
    {c, _} = Checkout.submit_address(checkout(), @address)
    assert {_, [step: :address]} = Checkout.goto(c, :address)
    assert {_, []} = Checkout.goto(checkout(), :payment)
  end

  test "payment outcomes" do
    {c, _} = Checkout.submit_address(checkout(), @address)
    assert {c, [step: :error]} = Checkout.failed(c, :declined)
    assert {_, [step: :complete, done: "https://pay"]} = Checkout.succeeded(c, "https://pay")
  end

  defp line(id, product_id, quantity),
    do: %{
      id: id,
      quantity: quantity,
      product: %{id: product_id, name: "W", description: "", thumbnail: "", amount: 1000}
    }

  defp at_payment(levels) do
    {c, _} = Checkout.submit_address(%{checkout() | stock_levels: fn _ -> levels end}, @address)
    c
  end

  test "checkout opens from the cart's stored lines; an empty cart can't" do
    assert {_, [blocked: :empty]} = Checkout.open(checkout(), {42, []})

    assert {_, [step: :address, form: %Ecto.Changeset{}]} =
             Checkout.open(checkout(), {42, [line(1, 7, 2)]})
  end

  test "paying takes the cart's id and lines: empty or out of stock blocks, otherwise the lines are charged" do
    assert {_, [blocked: :empty]} = Checkout.pay(at_payment(%{}), {42, []})

    assert {_, [blocked: :out_of_stock]} =
             Checkout.pay(at_payment(%{7 => 1}), {42, [line(1, 7, 2)]})

    assert {_, [step: :processing, ready_to_pay: {[%{unit_amount: 1000, quantity: 2}], 42}]} =
             Checkout.pay(at_payment(%{7 => 5}), {42, [line(1, 7, 2)]})
  end
end
