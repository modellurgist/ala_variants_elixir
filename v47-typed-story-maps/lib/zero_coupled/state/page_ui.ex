defmodule ZeroCoupled.State.PageUI do
  @moduledoc "Which of the page's tabs is showing. Port out: `:tab`."
  defstruct active_tab: :items, tabs: [:items]

  def ports, do: %{in: [switch_tab: :event], out: [tab: :tab]}

  def new(opts), do: %__MODULE__{tabs: opts[:tabs] || [:items]}

  def switch_tab(%__MODULE__{} = ui, %{tab: tab}) do
    if tab in ui.tabs, do: {%{ui | active_tab: tab}, [tab: tab]}, else: {ui, []}
  end
end
