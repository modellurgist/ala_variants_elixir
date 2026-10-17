defmodule GoodDealWeb.TraceTest do
  use ExUnit.Case, async: true

  alias GoodDealWeb.Paradigms.{Steps, Trace}

  defmodule Part do
    def ports, do: %{in: [], out: [done: :x, note: :x]}
    def poke(state, x), do: {state, [done: x]}
  end

  defmodule Page do
    @parts %{part: Part, other: Part}
    def features, do: @parts

    def poke(socket, x), do: Steps.run(socket, :part, &Part.poke(&1, x), &wire/3)
    defp wire(s, :part, {:done, x}), do: Steps.run(s, :other, &Part.poke(&1, x), &wire/3)
    defp wire(s, :other, {:done, _x}), do: Map.put(s, :landed, true)
  end

  test "hops are recorded as they run, landings included, and the unrouted outputs are the rest" do
    Trace.enable()

    socket =
      Page.poke(%Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, part: nil, other: nil}}, 1)

    assert socket.landed
    assert {:outside, :part} in Trace.edges(Page)
    assert {{:part, :done}, :other} in Trace.edges(Page)
    assert {{:other, :done}, :page} in Trace.edges(Page)
    assert Enum.sort(Trace.unrouted(Page)) == [other: :note, part: :note]
    chart = Trace.mermaid(Page)
    assert chart =~ ~s(part -->|"done"| other)
    assert chart =~ ~s(other -.->|"done"| page_other_done[page])
  end
end
