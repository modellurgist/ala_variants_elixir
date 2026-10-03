defmodule ZeroCoupled.Domain.StockIndicator do
  @moduledoc """
  A stock level shown as a coloured dot and a label, classified by a configured `StockStatus`
  (a domain UI component, so it sits beside the rule it uses).
  Config: `rule` (the `StockStatus`) and `labels`, one per status, where `%{n}` stands for the level.
  """
  use Phoenix.Component
  alias ZeroCoupled.Domain.StockStatus

  attr :stock, :integer, required: true
  attr :rule, StockStatus, required: true
  attr :labels, :map, required: true

  def stock_indicator(assigns) do
    assigns = assign(assigns, :status, StockStatus.call(assigns.rule, assigns.stock))

    ~H"""
    <span class={["inline-block w-2 h-2 rounded-full", dot(@status)]} />
    <span class={["text-sm", text(@status)]}>
      {String.replace(@labels[@status], "%{n}", Integer.to_string(@stock))}
    </span>
    """
  end

  defp dot(:in_stock), do: "bg-green-500"
  defp dot(:low_stock), do: "bg-amber-500"
  defp dot(:out_of_stock), do: "bg-red-500"
  defp text(:in_stock), do: "text-green-700"
  defp text(:low_stock), do: "text-amber-700"
  defp text(:out_of_stock), do: "text-red-700"
end
