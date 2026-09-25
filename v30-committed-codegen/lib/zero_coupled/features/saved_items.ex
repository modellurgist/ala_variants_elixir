# The save-for-later feature: one deletable file.

defmodule ZeroCoupled.Features.SavedItems do
  @moduledoc """
  The "saved for later" list — a zero-coupled peer. Items arrive as a
  reaction to the cart's `:item_saved` fact and leave via the
  `move_to_cart` intent (emitting `:moved_to_cart` for the cart).
  """

  @type t :: %__MODULE__{items: [map()]}

  defstruct items: []

  @spec init(keyword()) :: t()
  def init(_opts), do: %__MODULE__{}

  @spec list(t()) :: [map()]
  def list(%__MODULE__{items: items}), do: items

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{items: items}), do: length(items)

  @spec save(t(), map()) :: t()
  def save(%__MODULE__{} = saved, item) do
    if Enum.any?(saved.items, &(&1.id == item.id)),
      do: saved,
      else: %{saved | items: saved.items ++ [item]}
  end

  @doc "Remove an item by id, returning it so it can be moved elsewhere."
  @spec take(t(), term()) :: {t(), map() | nil}
  def take(%__MODULE__{} = saved, item_id) do
    case Enum.split_with(saved.items, &(&1.id == item_id)) do
      {[item | _], rest} -> {%{saved | items: rest}, item}
      {[], _} -> {saved, nil}
    end
  end
end

defmodule ZeroCoupled.Features.SavedItems.Facts do
  @moduledoc """
  Typed facts owned by the saved-items feature. Note the field name:
  `saved_item` — **this feature's own vocabulary**. The page manifest
  translates it to the cart reaction's `%{item: _}` port with a
  `transform:` — the emitter never bends its naming to a consumer.
  """

  defmodule MovedToCart do
    @moduledoc false
    @enforce_keys [:saved_item]
    defstruct [:saved_item]
  end
end

defmodule ZeroCoupled.Features.SavedItems.Intents do
  @moduledoc false
  use ZeroCoupled.Feature.Intents, slot: :saved

  alias ZeroCoupled.Effects
  alias ZeroCoupled.Features.SavedItems
  alias ZeroCoupled.Features.SavedItems.Facts

  # ── Intents ──────────────────────────────────────────────────────────

  intent :move_to_cart, params: [item_id: :int]

  def move_to_cart(session, %{item_id: item_id}) do
    case SavedItems.take(session.saved, item_id) do
      {saved, nil} ->
        {put_slot(session, saved), []}

      {saved, item} ->
        {put_slot(session, saved),
         [Effects.stream_delete(:saved_items, item), Effects.flash(:info, "Moved to cart")],
         [%Facts.MovedToCart{saved_item: item}]}
    end
  end

  # ── Reactions ────────────────────────────────────────────────────────

  @doc "Reaction to `:item_saved`: stash the item and show it in the saved stream."
  def stash(%SavedItems{} = saved, %{item: item}) do
    {SavedItems.save(saved, item), [Effects.stream_insert(:saved_items, item)]}
  end
end

defmodule ZeroCoupled.Features.SavedItems.Components do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true
  attr :item, :map, required: true

  def saved_row(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-[4rem_1fr_auto] items-center gap-4 border-b py-4">
      <img class="w-16 h-16 object-contain" src={@item.product.thumbnail} alt={@item.product.name} />
      <div>
        <div class="font-medium"><%= @item.product.name %></div>
        <div class="text-sm text-zinc-500"><%= Money.new(@item.product.amount) %></div>
      </div>
      <button phx-click="move_to_cart" phx-value-item-id={@item.id} class="text-sm font-medium text-blue-600">
        Move to cart
      </button>
    </div>
    """
  end
end
