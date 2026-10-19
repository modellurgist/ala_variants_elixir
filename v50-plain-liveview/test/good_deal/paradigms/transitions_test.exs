defmodule GoodDeal.Paradigms.TransitionsTest do
  use ExUnit.Case, async: true
  alias GoodDeal.Paradigms.Transitions

  @flow [{:address, :submit, :review}, {:review, :pay, :paying}, {:review, :edit, :address}]

  defp machine(at, url_edges \\ [{:review, :address}]),
    do: Transitions.new(flow: @flow, start: at, url_edges: url_edges)

  test "new takes the table, the starting step and the jumps; jumps default to none" do
    assert %Transitions{table: @flow, at: :address, jumps: [{:review, :address}]} =
             machine(:address)

    assert %Transitions{jumps: []} = Transitions.new(flow: @flow, start: :address)
    assert_raise KeyError, fn -> Transitions.new(start: :address) end
  end

  test "fire moves along the transition listed from the current step" do
    assert {:moved, :review, %Transitions{at: :review} = m} =
             Transitions.fire(machine(:address), :submit)

    assert {:moved, :paying, %Transitions{at: :paying, table: @flow}} = Transitions.fire(m, :pay)
  end

  test "fire stays on an unknown event or one listed only from another step" do
    assert :stayed = Transitions.fire(machine(:address), :nope)
    assert :stayed = Transitions.fire(machine(:address), :pay)
    assert :stayed = Transitions.fire(machine(:paying), :submit)
  end

  test "jump follows only an allowed edge from the current step" do
    assert {:moved, :address, %Transitions{at: :address}} =
             Transitions.jump(machine(:review), :address)

    assert :stayed = Transitions.jump(machine(:address), :review)
    assert :stayed = Transitions.jump(machine(:review), :paying)
    assert :stayed = Transitions.jump(machine(:paying), :address)
  end

  test "jump ignores the event table: a listed transition is not a URL edge" do
    assert :stayed = Transitions.jump(machine(:address, []), :review)
  end

  test "move goes anywhere, keeping the table and jumps" do
    m = machine(:paying)

    assert {:moved, :error, %Transitions{at: :error, table: @flow, jumps: [{:review, :address}]}} =
             Transitions.move(m, :error)

    assert {:moved, :paying, %Transitions{at: :paying}} = Transitions.move(m, :paying)
  end
end
