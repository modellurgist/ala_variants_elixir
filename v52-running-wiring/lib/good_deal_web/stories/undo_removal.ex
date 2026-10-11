defmodule GoodDealWeb.Stories.UndoRemoval do
  @moduledoc """
  A removed line can be taken back for a while: it's held, a notice offers to undo, and when the
  window closes the removal is final. Shared by the cart and the portal, each with its own window.
  Out: `:restored` (the line, to go back where it came from), `:expired` (its id, to make the removal
  final), `:pending` (whether to show the notice).
  """
  use GoodDealWeb, :html
  import GoodDeal.Components.Parts, only: [notice: 1]

  alias GoodDeal.State.Undo
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{undo: Undo}
  def events, do: ~w(undo_remove)

  def ports,
    do: %{
      in: [capture: :item, expire: :item],
      out: [restored: :item, expired: :item_id, pending: :flag]
    }

  @doc "Config: `window_ms`, how long a removal can be undone, and `timer`, the name the page gives its timer."
  def mount(s, opts, _out),
    do: assign(s, undo: Undo.new([]), undo_timer: {opts[:timer], opts[:window_ms]})

  def handle_event("undo_remove", _params, s, out), do: run(s, &Undo.restore(&1, nil), out)

  def input(s, :capture, item, out), do: run(s, &Undo.capture(&1, item), out)
  def input(s, :expire, item, out), do: run(s, &Undo.expire(&1, item.id), out)

  defp run(s, step, out), do: Steps.run(s, :undo, step, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :undo, {:captured, item}, out) do
    {timer, window_ms} = s.assigns.undo_timer
    s |> Steps.start_timer(timer, item, window_ms) |> out.({:pending, true})
  end

  defp wire(s, :undo, {:restored, item}, out) do
    {timer, _} = s.assigns.undo_timer
    s |> Steps.stop_timer(timer) |> out.({:pending, false}) |> out.({:restored, item})
  end

  defp wire(s, :undo, {:expired, item_id}, out),
    do: s |> out.({:pending, false}) |> out.({:expired, item_id})

  attr :pending, :boolean, required: true
  attr :t, :map, required: true, doc: "`text` and `undo`"

  def view(assigns) do
    ~H"""
    <.notice shown={@pending} text={@t.text} action={@t.undo} event="undo_remove" />
    """
  end
end
