defmodule GoodDealWeb.Stories.PriceOrder do
  @moduledoc """
  The buyer's order is priced by volume tier and taken to review from its total. Its part is the
  order's totals; the lines come in on `contents` from whichever story edits them. Out: `:summary`,
  `:review` (the summary, when the buyer wants to review).
  """
  use GoodDealWeb, :html
  import GoodDeal.Components.Parts, only: [primary_button: 1]
  import GoodDeal.Components.Rows, only: [order_summary: 1]

  alias GoodDeal.State.OrderTotals
  alias GoodDealWeb.Paradigms.Steps

  def parts, do: %{totals: OrderTotals}
  def events, do: ~w(go_review)
  def ports, do: %{in: [contents: :contents], out: [summary: :summary, review: :summary]}

  @doc "Config: `pricing` (`shipping`, `volume`)."
  def mount(s, opts, _out), do: assign(s, totals: OrderTotals.new(pricing: opts[:pricing]))

  def handle_event("go_review", _params, s, out),
    do: run(s, &OrderTotals.request_review(&1, nil), out)

  def input(s, :contents, contents, out), do: run(s, &OrderTotals.contents(&1, contents), out)

  defp run(s, step, out), do: Steps.run(s, :totals, step, &wire(&1, &2, &3, out))

  # {part, port} → where it wires inside this story, or out of it
  defp wire(s, :totals, {:summary, summary}, out), do: out.(s, {:summary, summary})
  defp wire(s, :totals, {:review, summary}, out), do: out.(s, {:review, summary})

  attr :summary, :map, required: true
  attr :t, :map, required: true

  def totals(assigns) do
    ~H"""
    <.order_summary summary={@summary} t={@t.summary} />
    <.primary_button event="go_review" disabled={@summary.empty?} class="mt-6 w-full">
      {@t.review} · {@summary.total}
    </.primary_button>
    """
  end
end
