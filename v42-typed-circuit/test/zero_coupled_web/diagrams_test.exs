defmodule ZeroCoupledWeb.DiagramsTest do
  use ExUnit.Case, async: true
  alias ZeroCoupled.Paradigms.Circuit
  alias ZeroCoupledWeb.{CartDiagram, PortalDiagram}

  defp cart, do: CartDiagram.circuit(%{cart_id: 1, charge: &ZeroCoupledWeb.CartPage.charge/1})

  test "both diagrams are valid" do
    assert %Circuit{} = Circuit.validate!(cart())
    assert %Circuit{} = Circuit.validate!(PortalDiagram.circuit(%{cart_id: 1}))
  end

  test "validation catches a typo'd port, a paradigm mismatch, a dropped wire, a bad feedback target, and a closure" do
    assert_raise ArgumentError, ~r/cart has no out port remved/, fn ->
      cart() |> Circuit.wire({:cart, :remved}, {:undo, :capture}) |> Circuit.validate!()
    end

    assert_raise ArgumentError, ~r/cart.summary \(summary\) -> undo.capture \(item\)/, fn ->
      cart() |> Circuit.wire({:cart, :summary}, {:undo, :capture}) |> Circuit.validate!()
    end

    dropped = %{cart() | wires: Map.delete(cart().wires, {:undo, :expired})}

    assert_raise ArgumentError, ~r/undo.expired is neither wired nor grounded/, fn ->
      Circuit.validate!(dropped)
    end

    bad_timer = put_in(cart().parts[:undo_clock].into, {:undo, :expires})

    assert_raise ArgumentError, ~r/undo_clock feeds back into undo.expires/, fn ->
      Circuit.validate!(bad_timer)
    end

    closure = put_in(cart().parts[:persist].write, fn _ -> :ok end)

    assert_raise ArgumentError, ~r/persist.write is an anonymous function/, fn ->
      Circuit.validate!(closure)
    end
  end

  test "the committed drawings are the diagrams that run" do
    for {file, text} <- ZeroCoupledWeb.Diagrams.drawings() do
      assert File.read!(file) == text, "#{file} is stale: run mix circuit.draw"
    end
  end
end
