defmodule ZeroCoupled.Effects do
  @moduledoc """
  The **effect vocabulary** — the one "programming paradigm" the pure
  layers speak to describe side effects as *data*.

  This is v28's answer to v27's `Outcome` module, which mixed
  domain-neutral effects (`flash`, `stream_insert`) with app-specific
  ones (`start_checkout`, `start_undo_timer`) as untyped atom tuples.
  Here every effect is a small **struct** (so typos are compile-time
  errors, not runtime crashes), the set is domain-neutral and stable,
  and the shell interprets them at the edge.

  Capabilities and the `Session` return `{state, [effect]}`. Because
  effects are inert data, tests assert on them directly — no Phoenix,
  no sockets. That is the "pleasant testing" property: the whole app's
  behaviour, including its side effects, is inspectable in a plain
  ExUnit assertion.
  """

  defmodule Flash do
    @moduledoc false
    defstruct [:level, :message]
    @type t :: %__MODULE__{level: atom(), message: String.t()}
  end

  defmodule Push do
    @moduledoc false
    defstruct [:event, :payload]
    @type t :: %__MODULE__{event: String.t(), payload: map()}
  end

  defmodule StreamInsert do
    @moduledoc false
    defstruct [:name, :item, at: -1]
    @type t :: %__MODULE__{name: atom(), item: term(), at: integer()}
  end

  defmodule StreamDelete do
    @moduledoc false
    defstruct [:name, :item]
    @type t :: %__MODULE__{name: atom(), item: term()}
  end

  defmodule StreamReset do
    @moduledoc false
    defstruct [:name, :items]
    @type t :: %__MODULE__{name: atom(), items: [term()]}
  end

  defmodule Patch do
    @moduledoc false
    defstruct [:to]
    @type t :: %__MODULE__{to: String.t()}
  end

  defmodule PatchFlow do
    @moduledoc """
    Patch the URL to a flow step's declared path (V33). The pure core names
    only `{flow, step}` — the path itself is web knowledge, resolved by the
    interpreter via the page's generated `flow_path/2`. A step without a
    path is a no-op.
    """
    defstruct [:flow, :step]
    @type t :: %__MODULE__{flow: atom(), step: atom()}
  end

  defmodule Navigate do
    @moduledoc false
    defstruct [:to]
    @type t :: %__MODULE__{to: String.t()}
  end

  defmodule Redirect do
    @moduledoc false
    defstruct [:to, :external]
    @type t :: %__MODULE__{to: String.t() | nil, external: String.t() | nil}
  end

  defmodule StartTimer do
    @moduledoc false
    defstruct [:name, :after_ms, :message]
    @type t :: %__MODULE__{name: atom(), after_ms: non_neg_integer(), message: term()}
  end

  defmodule CancelTimer do
    @moduledoc false
    defstruct [:name]
    @type t :: %__MODULE__{name: atom()}
  end

  defmodule Persist do
    @moduledoc "Cart persistence, described as data. Interpreted by the shell."
    defstruct [:op, :cart_id, :item_id, :quantity]
    @type t :: %__MODULE__{op: :update_quantity | :remove, cart_id: term(), item_id: term(), quantity: integer() | nil}
  end

  defmodule StartCheckout do
    @moduledoc false
    defstruct [:line_items, :metadata]
    @type t :: %__MODULE__{line_items: [map()], metadata: map()}
  end

  defmodule FinalizeOrder do
    @moduledoc "Record the order and draw down stock for a checked-out cart, described as data. Interpreted by the shell."
    defstruct [:cart_id]
    @type t :: %__MODULE__{cart_id: term()}
  end

  @type t ::
          Flash.t()
          | Push.t()
          | StreamInsert.t()
          | StreamDelete.t()
          | StreamReset.t()
          | Patch.t()
          | PatchFlow.t()
          | Navigate.t()
          | Redirect.t()
          | StartTimer.t()
          | CancelTimer.t()
          | Persist.t()
          | StartCheckout.t()
          | FinalizeOrder.t()

  # ── Constructors (ergonomic + arity-checked) ─────────────────────────

  def flash(level, message), do: %Flash{level: level, message: message}
  def push(event, payload \\ %{}), do: %Push{event: event, payload: payload}
  def stream_insert(name, item, at \\ -1), do: %StreamInsert{name: name, item: item, at: at}
  def stream_delete(name, item), do: %StreamDelete{name: name, item: item}
  def stream_reset(name, items), do: %StreamReset{name: name, items: items}
  def patch(to), do: %Patch{to: to}
  def patch_flow(flow, step), do: %PatchFlow{flow: flow, step: step}
  def navigate(to), do: %Navigate{to: to}
  def redirect_external(url), do: %Redirect{external: url}
  def start_timer(name, after_ms, message),
    do: %StartTimer{name: name, after_ms: after_ms, message: message}
  def cancel_timer(name), do: %CancelTimer{name: name}
  def persist_quantity(cart_id, item_id, quantity),
    do: %Persist{op: :update_quantity, cart_id: cart_id, item_id: item_id, quantity: quantity}
  def persist_remove(cart_id, item_id),
    do: %Persist{op: :remove, cart_id: cart_id, item_id: item_id}
  def start_checkout(line_items, metadata),
    do: %StartCheckout{line_items: line_items, metadata: metadata}

  def finalize_order(cart_id), do: %FinalizeOrder{cart_id: cart_id}
end
