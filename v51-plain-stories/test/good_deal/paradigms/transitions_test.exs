defmodule GoodDeal.Paradigms.TransitionsTest do
  use ExUnit.Case, async: true
  alias GoodDeal.Paradigms.Transitions

  @flow [{:address, :submit, :review}, {:review, :pay, :paying}, {:review, :edit, :address}]

  defp machine(step, jumps \\ [{:review, :address}]),
    do: Transitions.put(Transitions.new(@flow, :address, jumps), step)

  test "new starts at the start step; jumps default to none" do
    assert %Transitions{table: @flow, start: :address, step: :address, jumps: []} =
             Transitions.new(@flow, :address)
  end

  test "fire moves along the transition listed from the current step" do
    assert {:moved, %Transitions{step: :review} = m} =
             Transitions.fire(machine(:address), :submit)

    assert {:moved, %Transitions{step: :paying, start: :address}} = Transitions.fire(m, :pay)
  end

  test "fire stays, returning the machine unchanged, on an unknown or misplaced event" do
    m = machine(:address)
    assert {:stayed, ^m} = Transitions.fire(m, :nope)
    assert {:stayed, ^m} = Transitions.fire(m, :pay)
    assert {:stayed, _} = Transitions.fire(machine(:paying), :submit)
  end

  test "jump follows only an allowed edge from the current step" do
    assert {:moved, %Transitions{step: :address}} = Transitions.jump(machine(:review), :address)

    for {m, to} <- [{machine(:address), :review}, {machine(:review), :paying}] do
      assert {:stayed, ^m} = Transitions.jump(m, to)
    end
  end

  test "jump ignores the event table: a listed transition is not a URL edge" do
    m = machine(:address, [])
    assert {:stayed, ^m} = Transitions.jump(m, :review)
  end

  test "restart returns to the start step, keeping table and jumps" do
    m = machine(:paying)
    assert %{m | step: :address} == Transitions.restart(m)
  end

  test "put sets any step, listed or not, and changes nothing else" do
    m = machine(:review)
    assert %{m | step: :error} == Transitions.put(m, :error)
  end

  test "step answers the next state over a bare table" do
    assert {:moved, :review} = Transitions.step(@flow, :address, :submit)
    assert {:stayed, :address} = Transitions.step(@flow, :address, :pay)
  end
end
