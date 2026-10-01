defmodule GoodDeal.Features.UndoTest do
  use ExUnit.Case, async: true
  alias GoodDeal.Features.Undo

  @item %{id: 7, name: "thing"}

  test "capture holds the item and says so" do
    {undo, outs} = Undo.capture(Undo.new([]), @item)
    assert Undo.pending?(undo)
    assert outs == [captured: @item]
  end

  test "restore gives the item back" do
    {undo, _} = Undo.capture(Undo.new([]), @item)
    assert {undo, [restored: @item]} = Undo.restore(undo, nil)
    refute Undo.pending?(undo)
    assert {_, []} = Undo.restore(undo, nil)
  end

  test "a clock for an item no longer held is ignored" do
    {undo, _} = Undo.capture(Undo.new([]), @item)
    {undo, _} = Undo.capture(undo, %{id: 8})
    assert {_, []} = Undo.expire(undo, 7)
    assert {_, [expired: 8]} = Undo.expire(undo, 8)
  end

  test "a second removal makes the first final" do
    {undo, _} = Undo.capture(Undo.new([]), %{id: 1})
    assert {_, [expired: 1, captured: %{id: 2}]} = Undo.capture(undo, %{id: 2})
  end
end
