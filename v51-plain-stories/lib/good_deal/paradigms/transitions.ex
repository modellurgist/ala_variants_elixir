defmodule GoodDeal.Paradigms.Transitions do
  @moduledoc """
  The state-machine paradigm: a table of `{from, event, to}` and a current step. Firing an event
  moves along a listed transition or stays put; a jump (the URL asking for a step) is honoured only
  along a listed `{from, to}` edge. Both answer `{:moved, machine}` or `{:stayed, machine}`, so
  whoever holds the machine decides what a move announces. Knows nothing about checkouts or orders.
  V50 and V51B reshaped their own copies on 2026-10-19 with other APIs; the three aren't aligned.
  """

  @type table :: [{atom(), atom(), atom()}]

  defstruct table: [], start: nil, step: nil, jumps: []

  def new(table, start, jumps \\ []),
    do: %__MODULE__{table: table, start: start, step: start, jumps: jumps}

  def fire(%__MODULE__{} = m, event) do
    case step(m.table, m.step, event) do
      {:moved, to} -> {:moved, put(m, to)}
      {:stayed, _} -> {:stayed, m}
    end
  end

  def jump(%__MODULE__{} = m, to),
    do: if({m.step, to} in m.jumps, do: {:moved, put(m, to)}, else: {:stayed, m})

  def restart(%__MODULE__{} = m), do: put(m, m.start)

  @doc "Set the step outright, for an outcome the table doesn't list (a payment's result, say)."
  def put(%__MODULE__{} = m, to), do: %{m | step: to}

  @spec step(table(), atom(), atom()) :: {:moved, atom()} | {:stayed, atom()}
  def step(table, state, event) do
    case Enum.find(table, fn {from, ev, _to} -> from == state and ev == event end) do
      {_, _, to} -> {:moved, to}
      nil -> {:stayed, state}
    end
  end
end
