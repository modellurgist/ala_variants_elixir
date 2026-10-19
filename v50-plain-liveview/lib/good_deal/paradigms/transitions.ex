defmodule GoodDeal.Paradigms.Transitions do
  @moduledoc """
  The state-machine paradigm: a table of `{from, event, to}`, a current step, and the jumps (a URL
  asking for a step, say) allowed outside the table. Firing an event moves along a listed transition
  or stays put: `{:moved, to, machine}` or `:stayed`. Knows nothing about checkouts or orders. V51 and
  V51B reshaped their own copies on 2026-10-19 with other APIs; the three aren't aligned.
  """

  @type table :: [{atom(), atom(), atom()}]

  defstruct table: [], at: nil, jumps: []

  def new(opts),
    do: %__MODULE__{
      table: Keyword.fetch!(opts, :flow),
      at: Keyword.fetch!(opts, :start),
      jumps: Keyword.get(opts, :url_edges, [])
    }

  def fire(%__MODULE__{} = m, event) do
    case Enum.find(m.table, fn {from, ev, _to} -> from == m.at and ev == event end) do
      {_, _, to} -> move(m, to)
      nil -> :stayed
    end
  end

  def jump(%__MODULE__{} = m, to), do: if({m.at, to} in m.jumps, do: move(m, to), else: :stayed)

  @doc "Move unconditionally: a step the table doesn't hold, such as a restart or a payment outcome."
  def move(%__MODULE__{} = m, to), do: {:moved, to, %{m | at: to}}
end
