defmodule ZeroCoupled.Features.Undo.Banner do
  @moduledoc """
  The undo banner as a UI instance, holding the last removed line for a window. Config:
  `window_ms`, `text`. Inputs by `send_update`: `capture: item`, `expire: id`. It asks the page
  to return its clock: the clock fires `{:undo, :expire, id}` at the page, which sends it back
  here. Announces `{:undo, :restored, item}` and `{:undo, :expired, id}`.
  """
  use ZeroCoupledWeb, :live_component
  alias ZeroCoupled.Features.Undo
  alias ZeroCoupledWeb.Paradigms.Instance

  @doc "The ports this instance announces, as `{:undo, port, payload}`."
  def announces, do: [:restored, :expired]

  def mount(socket), do: {:ok, assign(socket, state: Undo.new([]), timer: nil)}
  def update(%{capture: item}, s), do: {:ok, step(s, &Undo.capture(&1, item))}
  def update(%{expire: id}, s), do: {:ok, step(s, &Undo.expire(&1, id))}
  def update(assigns, s), do: {:ok, assign(s, assigns)}

  def handle_event("undo_remove", _, s), do: {:noreply, step(s, &Undo.restore(&1, nil))}

  defp step(s, fun), do: Instance.step(s, fun, &land/2)

  defp land(s, {:captured, _}), do: s

  defp land(s, {:timer, {:start, id}}),
    do:
      assign(cancel(s),
        timer: Process.send_after(self(), {:undo, :expire, id}, s.assigns.window_ms)
      )

  defp land(s, {:timer, :cancel}), do: cancel(s)
  defp land(s, out), do: Instance.announce(s, :undo, out)

  defp cancel(%{assigns: %{timer: nil}} = s), do: s

  defp cancel(%{assigns: %{timer: ref}} = s),
    do:
      (
        Process.cancel_timer(ref)
        assign(s, timer: nil)
      )

  def render(assigns) do
    ~H"""
    <div>
      <div
        :if={Undo.pending?(@state)}
        class="flex items-center justify-between bg-amber-50 border border-amber-200 rounded-lg px-4 py-3 mb-4"
      >
        <span class="text-sm text-amber-800">{@text}</span>
        <button
          phx-click="undo_remove"
          phx-target={@myself}
          class="text-sm font-semibold text-amber-700 underline"
        >
          Undo
        </button>
      </div>
    </div>
    """
  end
end
