defmodule GoodDealWeb.Paradigms.Trace do
  @moduledoc """
  The wiring as it ran: every hop a page routed while the trace was on, from an output
  (`{key, port}`, or `:outside` for a browser event, a timer, a task result or a PubSub message) to
  the part it reached, or to `:page` when the clause kept it. A test run turns it on; off, `hop/3`
  is a no-op, so the pages pay nothing in production. `mermaid/1` draws a page from its hops and
  `unrouted/1` lists the declared outputs no hop ever left from.
  """
  alias GoodDealWeb.Paradigms.Wiring
  @table :ala_trace

  def enable do
    if :ets.whereis(@table) == :undefined,
      do: :ets.new(@table, [:bag, :public, :named_table])

    :ok
  end

  def enabled?, do: :ets.whereis(@table) != :undefined

  def hop(page, from, to),
    do: if(enabled?(), do: :ets.insert(@table, {page, from, to}), else: :ok)

  def edges(page),
    do: @table |> :ets.lookup(page) |> Enum.map(fn {_, from, to} -> {from, to} end) |> Enum.uniq()

  @doc "A page's declared outputs that no recorded hop left from: unwired, or never exercised by the run."
  def unrouted(page) do
    routed = page |> edges() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    page.features() |> Wiring.declared() |> Enum.reject(&MapSet.member?(routed, &1))
  end

  @doc "A Mermaid flowchart of the page as it ran: solid edges between parts, dotted ones that landed on the page."
  def mermaid(page) do
    edges =
      page
      |> edges()
      |> Enum.sort()
      |> Enum.map(fn
        {:outside, key} -> ~s(  outside --> #{key})
        {{key, port}, :page} -> ~s(  #{key} -.->|"#{port}"| page_#{key}_#{port}[page])
        {{key, port}, to} -> ~s(  #{key} -->|"#{port}"| #{to})
      end)

    (["flowchart LR"] ++ edges ++ [""]) |> Enum.join("\n")
  end
end
