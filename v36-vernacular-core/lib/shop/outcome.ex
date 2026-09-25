defmodule Shop.Outcome do
  @moduledoc """
  The effect vocabulary — the one non-default idea in V36, and a small,
  familiar one. Features return plain data describing side effects; the shell
  interprets it at the edge. Every outcome is built by a constructor function,
  so a typo is a compile error (V10's typed-outcomes property) — no atom-tuple
  guesswork.

  Vernacular on purpose: these are ordinary structs and functions. There is no
  macro, no behaviour to implement, nothing to `use`.
  """

  defmodule Flash do
    @moduledoc false
    defstruct [:level, :message]
  end

  defmodule StreamInsert do
    @moduledoc false
    defstruct [:name, :item]
  end

  defmodule StreamDelete do
    @moduledoc false
    defstruct [:name, :item]
  end

  defmodule StartTimer do
    @moduledoc false
    defstruct [:name, :after_ms, :message]
  end

  defmodule CancelTimer do
    @moduledoc false
    defstruct [:name]
  end

  defmodule Patch do
    @moduledoc false
    defstruct [:to]
  end

  def flash(level, message), do: %Flash{level: level, message: message}
  def stream_insert(name, item), do: %StreamInsert{name: name, item: item}
  def stream_delete(name, item), do: %StreamDelete{name: name, item: item}
  def start_timer(name, after_ms, message), do: %StartTimer{name: name, after_ms: after_ms, message: message}
  def cancel_timer(name), do: %CancelTimer{name: name}
  def patch(to), do: %Patch{to: to}
end
