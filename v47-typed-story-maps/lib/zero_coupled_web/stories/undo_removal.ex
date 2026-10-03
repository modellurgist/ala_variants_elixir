defmodule ZeroCoupledWeb.Stories.UndoRemoval do
  @moduledoc """
  A removed line can come back for a while. Its part is the undo offer; its timer, the window, reports
  back to its own `expire` input; its view is the notice with an Undo button. The cart page and the
  portal each place one, with their own window.
  """
  use ZeroCoupledWeb, :html
  @behaviour ZeroCoupledWeb.Paradigms.Binder
  import ZeroCoupled.Catalog.Parts, only: [notice: 1]

  alias ZeroCoupled.State.Undo
  alias ZeroCoupledWeb.Paradigms.Binder

  def parts, do: %{undo: Undo}
  def streams, do: []
  def events, do: ["undo_remove"]
  def ports, do: %{in: [capture: :item, expire: :item], out: [restored: :item, expired: :item_id]}

  @doc "Config: `window_ms`, how long a removal can be undone."
  def new(opts),
    do:
      Binder.story(__MODULE__, %{undo: Undo.new([])}, bindings(Keyword.fetch!(opts, :window_ms)),
        pending: false
      )

  # {source, port} → where it goes in this story; {:in, port} is the story's own input
  def bindings(window_ms) do
    %{
      {:in, :capture} => [{:input, :undo, &Undo.capture/2}],
      {:in, :expire} => [{:input, :undo, &Undo.expire/2}],
      {:undo, :captured} => [{:set, :pending, true}, {:start_timer, :undo, window_ms, :expire}],
      {:undo, :restored} => [{:stop_timer, :undo}, {:set, :pending, false}, {:out, :restored}],
      {:undo, :expired} => [{:set, :pending, false}, {:out, :expired}]
    }
  end

  def event(s, me, "undo_remove", _), do: Binder.run(s, me, :undo, &Undo.restore(&1, nil))

  attr :story, :map, required: true
  attr :t, :map, required: true, doc: "`text` and `undo`, from the page"

  def view(assigns) do
    ~H"""
    <.notice shown={@story.view.pending} text={@t.text} action={@t.undo} event="undo_remove" />
    """
  end
end
