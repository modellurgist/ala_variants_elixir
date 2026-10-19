defmodule GoodDeal.Paradigms.Transitions do
  @moduledoc """
  The state-machine paradigm: a table of `{from, event, to}`, a list of `{from, to}` jumps a URL may
  ask for, and a current state. Each function answers the state to be in next, which is the current
  one when the move isn't listed. Knows nothing about checkouts or orders. V50 and V51 reshaped their
  own copies on 2026-10-19 as structs with other APIs; the three aren't aligned.
  """

  @type table :: [{atom(), atom(), atom()}]
  @type edges :: [{atom(), atom()}]

  @spec next(table(), atom(), atom()) :: atom()
  def next(table, state, event) do
    case Enum.find(table, fn {from, ev, _to} -> from == state and ev == event end) do
      {_, _, to} -> to
      nil -> state
    end
  end

  @spec jump(edges(), atom(), atom()) :: atom()
  def jump(edges, state, to), do: if({state, to} in edges, do: to, else: state)
end
