defmodule GoodDeal.State.PageUI do
  @moduledoc "Which of the page's tabs is showing; a tab the page doesn't have is ignored."
  defstruct active_tab: :items, tabs: [:items]

  def new(opts), do: %__MODULE__{tabs: opts[:tabs] || [:items]}

  def switch_tab(%__MODULE__{} = ui, tab),
    do: if(tab in ui.tabs, do: %{ui | active_tab: tab}, else: ui)
end
