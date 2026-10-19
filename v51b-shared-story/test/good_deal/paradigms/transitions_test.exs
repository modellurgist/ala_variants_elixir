defmodule GoodDeal.Paradigms.TransitionsTest do
  use ExUnit.Case, async: true
  alias GoodDeal.Paradigms.Transitions

  @flow [{:address, :submit, :review}, {:review, :pay, :paying}, {:review, :edit, :address}]
  @edges [{:review, :address}]

  test "next moves along the transition listed from the current state" do
    assert Transitions.next(@flow, :address, :submit) == :review
    assert Transitions.next(@flow, :review, :pay) == :paying
    assert Transitions.next(@flow, :review, :edit) == :address
  end

  test "next stays on an unknown event, one listed only from another state, or an empty table" do
    assert Transitions.next(@flow, :address, :nope) == :address
    assert Transitions.next(@flow, :address, :pay) == :address
    assert Transitions.next(@flow, :paying, :submit) == :paying
    assert Transitions.next([], :address, :submit) == :address
  end

  test "jump follows only an allowed edge from the current state" do
    assert Transitions.jump(@edges, :review, :address) == :address
    assert Transitions.jump(@edges, :address, :review) == :address
    assert Transitions.jump(@edges, :review, :paying) == :review
    assert Transitions.jump([], :review, :address) == :review
  end
end
