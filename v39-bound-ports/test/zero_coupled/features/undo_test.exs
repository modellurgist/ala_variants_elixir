defmodule ZeroCoupled.Features.UndoTest do
  use ExUnit.Case, async: true
  alias ZeroCoupled.Features.Undo

  @item %{id: 7, name: "thing"}

  test "capture holds the item and asks for a clock" do
    {undo, outs} = Undo.capture(Undo.new([]), @item)
    assert Undo.pending?(undo)
    assert outs == [captured: @item, timer: {:start, 7}]
  end

  test "restore gives the item back and cancels the clock" do
    {undo, _} = Undo.capture(Undo.new([]), @item)
    assert {undo, [restored: @item, timer: :cancel]} = Undo.restore(undo, nil)
    refute Undo.pending?(undo)
    assert {_, []} = Undo.restore(undo, nil)
  end

  test "a clock for an item no longer held is ignored" do
    {undo, _} = Undo.capture(Undo.new([]), @item)
    {undo, _} = Undo.capture(undo, %{id: 8})
    assert {_, []} = Undo.expire(undo, 7)
    assert {_, [expired: 8]} = Undo.expire(undo, 8)
  end
end
