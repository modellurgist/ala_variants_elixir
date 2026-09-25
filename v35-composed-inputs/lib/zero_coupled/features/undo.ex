# The undo-removal feature: one deletable file.
#   Undo            — pure capability (private struct; knows nothing of Cart)
#   Undo.Intents    — the undo button's intents + the reaction that arms it
#   Undo.Components — the undo banner markup

defmodule ZeroCoupled.Features.Undo do
  @moduledoc """
  Holds the last removed item during the undo window. A genuine
  zero-coupled peer: it never references the cart; the manifest wires
  removed items in and restored items out (as facts).
  """

  @type t :: %__MODULE__{pending: nil | %{item: map()}, window_ms: non_neg_integer() | nil}

  defstruct pending: nil, window_ms: nil

  @doc "Build the slot; the undo window is composition config (manifest `config:`)."
  @spec init(keyword()) :: t()
  def init(opts), do: %__MODULE__{window_ms: (opts[:config] || [])[:window_ms]}

  @spec pending?(t()) :: boolean()
  def pending?(%__MODULE__{pending: nil}), do: false
  def pending?(%__MODULE__{}), do: true

  @spec capture(t(), map()) :: t()
  def capture(%__MODULE__{} = undo, item), do: %{undo | pending: %{item: item}}

  @doc "Return the pending item (if any) and clear it."
  @spec take(t()) :: {t(), map() | nil}
  def take(%__MODULE__{pending: nil} = undo), do: {undo, nil}
  def take(%__MODULE__{pending: %{item: item}} = undo), do: {%{undo | pending: nil}, item}

  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = undo), do: %{undo | pending: nil}

  @doc "L5 presentation port (`render: :render_data` → `@undo`)."
  @spec render_data(t()) :: map()
  def render_data(%__MODULE__{} = undo), do: %{pending?: pending?(undo)}
end

defmodule ZeroCoupled.Features.Undo.Facts do
  @moduledoc "Typed facts owned by the undo feature (see CartItems.Facts for the pattern)."

  defmodule ItemRestored do
    @moduledoc false
    @enforce_keys [:item]
    defstruct [:item]
  end

  defmodule RemovalFinal do
    @moduledoc false
    @enforce_keys [:item_id]
    defstruct [:item_id]
  end

  defmodule UndoExpired do
    @moduledoc """
    The undo timer's message, typed (V32 Enhancement B): the timer effect
    carries this struct instead of a bare `{:undo_expired, id}` tuple, so
    the page's `handle_info` matches a compile-checked shape. It routes to
    the `undo_expired` *intent* (not a manifest reaction — it emits
    `RemovalFinal`, and reactions are single-level by rule).
    """
    @enforce_keys [:item_id]
    defstruct [:item_id]
  end
end

defmodule ZeroCoupled.Features.Undo.Intents do
  @moduledoc false
  use ZeroCoupled.Feature.Intents, slot: :undo

  alias ZeroCoupled.Effects
  alias ZeroCoupled.Features.Undo
  alias ZeroCoupled.Features.Undo.Facts

  # ── Intents ──────────────────────────────────────────────────────────

  intent :undo_remove

  def undo_remove(session, _args) do
    case Undo.take(session.undo) do
      {undo, nil} ->
        {put_slot(session, undo), []}

      {undo, item} ->
        {put_slot(session, undo),
         [Effects.cancel_timer(:undo), Effects.flash(:info, "Item restored")],
         [%Facts.ItemRestored{item: item}]}
    end
  end

  @doc "Irregular (from handle_info): the undo timer fired."
  def undo_expired(session, item_id) do
    case session.undo.pending do
      nil ->
        {session, []}

      _pending ->
        {put_slot(session, Undo.clear(session.undo)), [],
         [%Facts.RemovalFinal{item_id: item_id}]}
    end
  end

  # ── Reactions ────────────────────────────────────────────────────────

  @doc "Reaction to `:item_removed`: remember the item and arm the timer (window from config)."
  def capture_removed(%Undo{} = undo, %{item: item, item_id: item_id}) do
    {Undo.capture(undo, item),
     [
       Effects.start_timer(:undo, undo.window_ms, %Facts.UndoExpired{item_id: item_id}),
       Effects.flash(:info, "Item removed — undo?")
     ]}
  end
end

defmodule ZeroCoupled.Features.Undo.Components do
  @moduledoc false
  use Phoenix.Component

  alias ZeroCoupled.Web.Contracts

  def undo_banner(assigns) do
    ~H"""
    <div class="flex items-center justify-between bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 mb-4">
      <span class="text-sm text-amber-800">Item removed.</span>
      <button phx-click={Contracts.event(:undo_remove)} class="text-sm font-semibold text-amber-700 underline">
        Undo
      </button>
    </div>
    """
  end
end
