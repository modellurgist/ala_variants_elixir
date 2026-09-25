defmodule ZeroCoupled.Features.UndoTest do
  use ExUnit.Case, async: true

  import ZeroCoupled.CartFixtures
  alias ZeroCoupled.Features.Undo

  test "init/1 has nothing pending" do
    refute Undo.pending?(Undo.init([]))
  end

  test "captures an item and reports pending" do
    undo = Undo.init([]) |> Undo.capture(line_item(1))
    assert Undo.pending?(undo)
  end

  test "take returns the captured item and clears" do
    undo = Undo.init([]) |> Undo.capture(line_item(1))
    assert {undo, %{id: 1}} = Undo.take(undo)
    refute Undo.pending?(undo)
  end

  test "take on empty returns nil" do
    assert {_undo, nil} = Undo.take(Undo.init([]))
  end

  test "capture replaces the previous pending item" do
    undo = Undo.init([]) |> Undo.capture(line_item(1)) |> Undo.capture(line_item(2))
    assert {_undo, %{id: 2}} = Undo.take(undo)
  end

  test "clear drops any pending item" do
    undo = Undo.init([]) |> Undo.capture(line_item(1)) |> Undo.clear()
    refute Undo.pending?(undo)
  end
end
