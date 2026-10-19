defmodule GoodDealWeb.UndoRemoval do
  @moduledoc """
  Deferred removal of a cart item, shared by the cart page and the portal.

  The item stays in the database while the undo window is open and is deleted
  when the window elapses or when another removal replaces it, so only the most
  recent removal can be undone. The LiveView must forward
  `{:undo_expired, item_id}` messages to `expire/2`.
  """
  import Phoenix.Component, only: [assign: 3]

  alias GoodDeal.ShoppingCart

  def init(socket), do: assign(socket, :pending_removal, nil)

  def remove(socket, item) do
    socket = finalize(socket)
    timer = Process.send_after(self(), {:undo_expired, item.id}, window())
    assign(socket, :pending_removal, %{item: item, timer: timer})
  end

  @doc """
  Restores the pending item. Returns `{item_or_nil, socket}`.
  """
  def undo(%{assigns: %{pending_removal: %{item: item, timer: timer}}} = socket) do
    Process.cancel_timer(timer)
    {:ok, item} = ShoppingCart.restore_item(item)
    {item, assign(socket, :pending_removal, nil)}
  end

  def undo(socket), do: {nil, socket}

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

  defp window, do: Application.fetch_env!(:good_deal, :undo_window_ms)
end
