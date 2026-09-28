defmodule ZeroCoupled.Features.CheckoutTest do
  use ExUnit.Case, async: true
  alias ZeroCoupled.Features.Checkout

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
        stock_levels: fn _ -> %{} end
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
end
