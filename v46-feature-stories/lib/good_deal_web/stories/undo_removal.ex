defmodule GoodDealWeb.Stories.UndoRemoval do
  @moduledoc """
  A removed line can come back for a while. Its part is the undo offer; its view is the notice with
  an Undo button; its timer is the window. Used on the cart page and the portal, each configuring its
  own window. Ports: `capture` a removed line, and `expire` it when its timer reports the window closed; out, the line
  `restored` or the id whose removal is now `expired`.
  """
  use GoodDealWeb, :html
  @behaviour GoodDealWeb.Paradigms.Story
  import GoodDeal.Components.Parts, only: [notice: 1]

  alias GoodDeal.State.Undo
  alias GoodDealWeb.Paradigms.{Sinks, Story}

  def parts, do: %{undo: Undo}
  def streams, do: []
  def events, do: ["undo_remove"]

  def ports,
    do: %{in: [capture: :item, expire: :item], out: [restored: :item, expired: :item_id]}

  @doc "Config: `window_ms`, how long a removal can be undone."
  def new(opts),
    do:
      Story.new(__MODULE__, %{undo: Undo.new([])},
        timers: %{undo: {Keyword.fetch!(opts, :window_ms), :expire}},
        view: [pending: false]
      )

  def input(s, me, :capture, item), do: Story.run(s, me, :undo, &Undo.capture(&1, item))
  def input(s, me, :expire, item), do: Story.run(s, me, :undo, &Undo.expire(&1, item))

  def event(s, me, "undo_remove", _), do: Story.run(s, me, :undo, &Undo.restore(&1, nil))

  # {part, port} → where it wires inside this story, or out of it
  def wire(s, me, :undo, {:captured, item}),
    do: s |> Story.show(me, :pending, true) |> Story.start_timer(me, :undo, item)

  def wire(s, me, :undo, {:restored, item}),
    do:
      s
      |> Sinks.stop_timer(:undo)
      |> Story.show(me, :pending, false)
      |> Story.send_out(me, :restored, item)

  def wire(s, me, :undo, {:expired, item_id}),
    do: s |> Story.show(me, :pending, false) |> Story.send_out(me, :expired, item_id)

  attr :story, :map, required: true
  attr :t, :map, required: true, doc: "`text` and `undo`, from the page"

  def view(assigns) do
    ~H"""
    <.notice shown={@story.view.pending} text={@t.text} action={@t.undo} event="undo_remove" />
    """
  end
end
