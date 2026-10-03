defmodule ZeroCoupled.Features.Undo.Banner do
  @moduledoc """
  The undo banner as a UI instance, holding the last removed line for a window. Config:
  `window_ms`, `text`. Inputs by `send_update`: `capture: item`, `expire: id`. It asks the page
  to return its clock: the clock fires `{:undo, :expire, id}` at the page, which sends it back
  here. Sends the page `{:undo, :restored, item}` and `{:undo, :expired, id}`.
  """
  use ZeroCoupledWeb, :live_component
  alias ZeroCoupled.Features.Undo
  alias ZeroCoupledWeb.Paradigms.Instance

  # outputs this instance shows itself; every other port its feature declares is sent
  @wired_here [:captured]

  @doc "The ports this instance sends the page, as `{name, port, payload}`."
  def sent_port_outputs, do: Keyword.keys(Undo.ports().out) -- @wired_here

  def mount(socket), do: {:ok, assign(socket, state: Undo.new([]), timer: nil)}
  def update(%{capture: item}, s), do: {:ok, step(s, &Undo.capture(&1, item))}
  def update(%{expire: id}, s), do: {:ok, step(s, &Undo.expire(&1, id))}
  def update(assigns, s), do: {:ok, assign(s, assigns)}

  def handle_event("undo_remove", _, s), do: {:noreply, step(s, &Undo.restore(&1, nil))}

  defp step(s, fun), do: Instance.step(s, fun, &wire/2)

  # the offer's clock: started when a line is held, stopped when it comes back
  defp wire(s, {:captured, item}),
    do:
      assign(cancel(s),
        timer: Process.send_after(self(), {:undo, :expire, item.id}, s.assigns.window_ms)
      )

  defp wire(s, {:restored, _} = out), do: s |> cancel() |> Instance.send_port_output(:undo, out)
  defp wire(s, out), do: Instance.send_port_output(s, :undo, out)

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
          {@t.undo}
        </button>
      </div>
    </div>
    """
  end
end
