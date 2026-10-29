defmodule GoodDealWeb.UndoRemoval do
  @moduledoc """
  Deferred removal of a cart item, shared by the cart page and the portal.

  The item stays in the database while the undo window is open and is deleted
  when the window elapses or when another removal replaces it, so only the most
  recent removal can be undone. A page configures it once, in its parts, with the
  stream that shows the item and the window, and must forward `{:undo_expired, item_id}`
  messages to `expire/2`.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, stream_delete: 3, stream_insert: 3]

  alias GoodDeal.ShoppingCart

  @enforce_keys [:stream, :window_ms]
  defstruct @enforce_keys

  def init(socket), do: assign(socket, :pending_removal, nil)

  def remove(socket, %__MODULE__{} = config, item) do
    socket = finalize(socket)
    timer = Process.send_after(self(), {:undo_expired, item.id}, config.window_ms)

    socket
    |> assign(:pending_removal, %{item: item, timer: timer})
    |> stream_delete(config.stream, item)
  end

  def undo(
        %{assigns: %{pending_removal: %{item: item, timer: timer}}} = socket,
        %__MODULE__{} = config
      ) do
    Process.cancel_timer(timer)
    {:ok, item} = ShoppingCart.restore_item(item)

    socket
    |> assign(:pending_removal, nil)
    |> stream_insert(config.stream, item)
    |> put_flash(:info, "Item restored")
  end

  def undo(socket, %__MODULE__{}), do: socket

  def expire(%{assigns: %{pending_removal: %{item: %{id: id}}}} = socket, id),
    do: finalize(socket)

  def expire(socket, _stale_id), do: socket

  def finalize(%{assigns: %{pending_removal: %{item: item, timer: timer}}} = socket) do
    Process.cancel_timer(timer)
    :ok = ShoppingCart.delete_item(item)
    assign(socket, :pending_removal, nil)
  end

  def finalize(socket), do: socket

  def pending_id(%{assigns: %{pending_removal: %{item: item}}}), do: item.id
  def pending_id(_socket), do: nil
end
