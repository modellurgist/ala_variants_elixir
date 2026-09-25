defmodule ZeroCoupledWeb.CartLive.CheckoutViewTest do
  @moduledoc """
  ActionViews are plain functions of assigns, so we render them in
  isolation with `render_component/2` — fast, no LiveView process, no DB.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import Phoenix.Component, only: [to_form: 1]
  import ZeroCoupled.CartFixtures

  alias ZeroCoupledWeb.CartLive.CheckoutView
  alias ZeroCoupledWeb.CartPage
  alias ZeroCoupled.Features.CheckoutFlow

  @endpoint ZeroCoupledWeb.Endpoint
  @valid %{"name" => "Ada", "line1" => "1 Analytical Ave", "city" => "London", "postal_code" => "12345"}

  # Per-slot assigns: the ActionView declares exactly the inputs it
  # needs — the checkout slot and the cart presentation port.
  defp assigns(session) do
    %{
      checkout_slot: session.checkout,
      cart: ZeroCoupled.Features.CartItems.render_data(session.cart),
      address_form: to_form(CheckoutFlow.address_changeset(session.checkout, %{})),
      live_action: :checkout
    }
  end

  defp session, do: CartPage.Session.new(cart_id: 1, items: [line_item(1, amount: 1000)])

  test "address step renders the form" do
    html = render_component(&CheckoutView.render/1, assigns(session()))
    assert html =~ "Full name"
    assert html =~ "Continue to payment"
  end

  test "payment step renders the address summary and total" do
    {:ok, session, _effects} = CheckoutFlow.Intents.submit_address(session(), @valid)

    html = render_component(&CheckoutView.render/1, assigns(session))
    assert html =~ "Ada"
    assert html =~ "London"
    assert html =~ "Pay"
  end

  test "processing step renders a spinner" do
    session = session()
    session = %{session | checkout: %{session.checkout | step: :processing}}
    html = render_component(&CheckoutView.render/1, assigns(session))
    assert html =~ "Processing payment"
  end

  test "error step offers a retry" do
    session = session()
    session = %{session | checkout: %{session.checkout | step: :error}}
    html = render_component(&CheckoutView.render/1, assigns(session))
    assert html =~ "Payment failed"
    assert html =~ "Try again"
  end
end
