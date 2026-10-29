defmodule GoodDealWeb.Paradigms.Trace do
  @moduledoc """
  The wiring as it ran. `Steps.to/7` and `Steps.out/5` record every hop a page routes (a browser
  event into a story, a story's output into another story, or a story's output landing on the page)
  while the table is on, so a test run draws the diagram from the code that ran and reports a
  declared output that never routed anywhere. Knows nothing of any page: a page names itself when it
  records.
  """

  @table :ala_trace

  def enable,
    do:
      if(:ets.whereis(@table) == :undefined,
        do: :ets.new(@table, [:bag, :public, :named_table]),
        else: @table
      )

  def enabled?, do: :ets.whereis(@table) != :undefined

  @doc "Record one hop of `page`'s wiring: from `{key, port}` (or `:browser`) to `{key, input}` (or `:page`)."
  def hop(page, from, to),
    do: if(enabled?(), do: :ets.insert(@table, {page, from, to}), else: :ok)

  def edges(page),
    do: @table |> :ets.lookup(page) |> Enum.map(fn {_, from, to} -> {from, to} end) |> Enum.uniq()

  @doc "A page's declared outputs that no recorded hop left from: unwired, or never exercised by the run."
  def unrouted(page) do
    routed = page |> edges() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    for {key, part} <- page.parts(),
        port <- Keyword.keys(part.ports().out),
        not MapSet.member?(routed, {key, port}),
        {key, port} not in GoodDealWeb.Paradigms.Wiring.grounded(page),
        do: {key, port}
  end

  @doc "The page's diagram from the hops that ran."
  def mermaid(page) do
    edges =
      page
      |> edges()
      |> Enum.sort()
      |> Enum.map(fn
        {:outside, {key, input}} -> ~s(  outside -->|"#{input}"| #{key})
        {{key, port}, :page} -> ~s(  #{key} -.->|"#{port}"| page_#{key}_#{port}[page])
        {{key, port}, {to, input}} -> ~s(  #{key} -->|"#{port} → #{input}"| #{to})
      end)

    Enum.join(["flowchart LR" | edges], "\n") <> "\n"
  end
end
