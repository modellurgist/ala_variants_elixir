defmodule ZeroCoupled.Paradigms.Transitions do
  @moduledoc """
  The state-machine paradigm: a table of `{from, event, to}` and a current state. Stepping with
  an event moves along a listed transition or stays put. Knows nothing about checkouts or orders.
  """

  @type table :: [{atom(), atom(), atom()}]

  @spec step(table(), atom(), atom()) :: {:moved, atom()} | {:stayed, atom()}
  def step(table, state, event) do
    case Enum.find(table, fn {from, ev, _to} -> from == state and ev == event end) do
      {_, _, to} -> {:moved, to}
      nil -> {:stayed, state}
    end
  end
end
