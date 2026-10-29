defmodule GoodDealWeb.TraceTest do
  use ExUnit.Case, async: true

  alias GoodDealWeb.Paradigms.{Steps, Trace}

  defmodule Story do
    def ports, do: %{in: [poke: :x], out: [done: :x, note: :x]}
    def input(socket, :poke, x, out), do: out.(socket, {:done, x})
  end

  defmodule Page do
    @parts %{story: Story, other: Story}
    def parts, do: @parts

    def to(socket, key, port, payload),
      do: Steps.to(socket, __MODULE__, @parts, key, port, payload, out(key))

    defp out(key), do: fn s, output -> Steps.out(s, __MODULE__, key, output, &wire/3) end
    defp wire(s, :story, {:done, x}), do: to(s, :other, :poke, x)
    defp wire(s, :other, {:done, _x}), do: Map.put(s, :landed, true)
  end

  test "hops are recorded as they run, landings included, and the unrouted outputs are the rest" do
    Trace.enable()
    socket = Page.to(%{private: %{}}, :story, :poke, 1)
    assert socket.landed
    assert {:outside, {:story, :poke}} in Trace.edges(Page)
    assert {{:story, :done}, {:other, :poke}} in Trace.edges(Page)
    assert {{:other, :done}, :page} in Trace.edges(Page)
    assert Enum.sort(Trace.unrouted(Page)) == [other: :note, story: :note]
    chart = Trace.mermaid(Page)
    assert chart =~ ~s(story -->|"done → poke"| other)
    assert chart =~ ~s(other -.->|"done"| page_other_done[page])
  end
end
