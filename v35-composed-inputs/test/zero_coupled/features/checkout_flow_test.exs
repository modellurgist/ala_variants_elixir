defmodule ZeroCoupled.Features.CheckoutFlowTest do
  use ExUnit.Case, async: true

  alias ZeroCoupled.Features.CheckoutFlow

  @valid %{"name" => "Ada", "line1" => "1 Analytical Ave", "city" => "London", "postal_code" => "12345"}

  test "starts on the address step" do
    assert CheckoutFlow.init([]).step == :address
  end

  test "address_changeset validates required fields" do
    refute CheckoutFlow.address_changeset(CheckoutFlow.init([]), %{}).valid?
  end

  test "submit_address advances to payment on valid input" do
    assert {:ok, checkout} = CheckoutFlow.submit_address(CheckoutFlow.init([]), @valid)
    assert checkout.step == :payment
    assert checkout.address.name == "Ada"
  end

  test "submit_address returns an errored changeset on invalid input" do
    assert {:error, changeset} =
             CheckoutFlow.submit_address(CheckoutFlow.init([]), %{@valid | "postal_code" => "abc"})

    assert %{postal_code: ["must be 4–10 digits"]} = errors_on(changeset)
  end

  test "the full step machine (UI edges off the flow table, result edges direct)" do
    {:ok, checkout} = CheckoutFlow.submit_address(CheckoutFlow.init([]), @valid)
    assert checkout.step == :payment
    assert CheckoutFlow.goto(checkout, CheckoutFlow.advance(checkout, :edit_address)).step == :address
    assert CheckoutFlow.goto(checkout, CheckoutFlow.advance(checkout, :pay)).step == :processing
    assert CheckoutFlow.complete(checkout, "https://pay").step == :complete
    assert CheckoutFlow.complete(checkout, "https://pay").url == "https://pay"
    assert CheckoutFlow.fail(checkout).step == :error
    assert CheckoutFlow.reset(checkout).step == :address
  end

  test "an undeclared edge is a no-op goto" do
    checkout = CheckoutFlow.init([])
    assert CheckoutFlow.advance(checkout, :pay) == :no_transition
    assert CheckoutFlow.goto(checkout, :no_transition).step == :address
  end

  test "URL policy: only the backward edge is jumpable" do
    {:ok, at_payment} = CheckoutFlow.submit_address(CheckoutFlow.init([]), @valid)
    assert CheckoutFlow.can_goto?(at_payment, :address)
    refute CheckoutFlow.can_goto?(CheckoutFlow.init([]), :payment)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
