defmodule ShopWeb.CartShell do
  @moduledoc """
  The imperative shell — the only part that touches the outside world. It runs
  an action through the composition and interprets the returned outcomes at the
  edge. Kept dependency-free here (a `view` map stands in for a LiveView
  socket) so the variant compiles and tests without Phoenix; a real LiveView is
  a 3-line delegation:

      def handle_event(name, params, socket) do
        {page, view} = ShopWeb.CartShell.dispatch(socket.assigns.page, socket.assigns.view,
                          String.to_existing_atom(name), cast(params))
        {:noreply, socket |> assign(page: page, view: view)}
      end

  Everything above the shell is pure and framework-free.
  """
  alias ShopWeb.CartPage
  alias Shop.Outcome

  @doc "Fresh view accumulator (stands in for the socket's rendered state)."
  def view, do: %{flashes: [], streams: %{}, timers: %{}, patch: nil}

  @doc "Run one action: pure composition → interpret its outcomes into the view."
  def dispatch(page, view, action, args) do
    {page, outcomes} = CartPage.handle(action, args, page)
    {page, Enum.reduce(outcomes, view, &apply_outcome/2)}
  end

  defp apply_outcome(%Outcome.Flash{} = f, v), do: %{v | flashes: v.flashes ++ [{f.level, f.message}]}

  defp apply_outcome(%Outcome.StreamInsert{name: n, item: i}, v),
    do: put_in(v, [:streams, n], Map.get(v.streams, n, %{}) |> Map.put(i.id, i))

  defp apply_outcome(%Outcome.StreamDelete{name: n, item: i}, v),
    do: update_in(v, [:streams, n], &Map.delete(&1 || %{}, i.id))

  defp apply_outcome(%Outcome.StartTimer{name: n, message: m}, v), do: put_in(v, [:timers, n], m)
  defp apply_outcome(%Outcome.CancelTimer{name: n}, v), do: update_in(v, [:timers], &Map.delete(&1, n))
  defp apply_outcome(%Outcome.Patch{to: to}, v), do: %{v | patch: to}
end
