defmodule ZeroCoupled.Paradigms.CircuitTest do
  use ExUnit.Case, async: true
  alias ZeroCoupled.Paradigms.{Adapter, Circuit, ToAssign, ToFlash, ToTimer, Via}

  defmodule Counter do
    defstruct n: 0

    def bump(%{n: n} = c, by),
      do: {%{c | n: n + by}, [count: n + by, big: n + by > 2, raw: n + by]}
  end

  defmodule Flag do
    defstruct on: false
    def set(f, on), do: {%{f | on: on}, [on: on]}
  end

  defp circuit do
    Circuit.new(
      counter: Adapter.new(Counter, %Counter{}),
      flag: Adapter.new(Flag, %Flag{}),
      count: %ToAssign{name: :count},
      tens: %Via{fun: &(&1 * 10)},
      tens_out: %ToAssign{name: :tens},
      notice: %ToFlash{texts: %{true => "big now"}},
      clock: %ToTimer{name: :tick, ms: 10, into: {:flag, :set}}
    )
    |> Circuit.wire({:counter, :count}, {:count, :value})
    |> Circuit.wire({:counter, :count}, {:tens, :in})
    |> Circuit.wire({:tens, :out}, {:tens_out, :value})
    |> Circuit.wire({:counter, :big}, {:flag, :set})
    |> Circuit.wire({:flag, :on}, {:notice, :key})
  end

  test "outputs travel the wires, through transforms and into other features; the edge gets the ui effects" do
    {c, edge} = Circuit.push(circuit(), :counter, {:bump, 3})
    assert Circuit.part(c, :counter).state.n == 3
    assert Circuit.part(c, :flag).state.on == true

    assert edge == [
             {{:count, :ui}, {:assign, :count, 3}},
             {{:tens_out, :ui}, {:assign, :tens, 30}},
             {{:notice, :ui}, {:flash, :info, "big now"}},
             {{:counter, :raw}, 3}
           ]
  end

  test "an unwired feature port reaches the edge under its own name; a keyed flash with no text is quiet" do
    {_, edge} = Circuit.push(circuit(), :counter, {:bump, 1})
    assert {{:counter, :raw}, 1} in edge
    refute Enum.any?(edge, &match?({{:notice, :ui}, _}, &1))
  end

  test "a timer sink describes the message that will come back into the circuit" do
    {_, edge} = Circuit.push(circuit(), :clock, {:value, {:start, true}})
    assert edge == [{{:clock, :ui}, {:timer_start, :tick, 10, {:feed, :flag, {:set, true}}}}]
  end
end
