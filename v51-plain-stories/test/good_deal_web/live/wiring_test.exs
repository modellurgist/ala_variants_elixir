defmodule GoodDealWeb.WiringTest do
  use ExUnit.Case, async: true
  alias GoodDealWeb.Paradigms.Wiring

  test "the cart page wires every declared port, and nothing else" do
    assert Wiring.gaps(GoodDealWeb.CartLive.Show) == %{unwired: [], unknown: []}
  end

  test "the product pages wire every port of their record form" do
    assert Wiring.gaps(GoodDealWeb.ProductLive.Index) == %{unwired: [], unknown: []}
    assert Wiring.gaps(GoodDealWeb.ProductLive.Show) == %{unwired: [], unknown: []}
  end

  test "the portal wires every declared port, and nothing else" do
    assert Wiring.gaps(GoodDealWeb.PortalLive.Show) == %{unwired: [], unknown: []}
  end

  @stories [
    GoodDealWeb.Stories.EditCart,
    GoodDealWeb.Stories.UndoRemoval,
    GoodDealWeb.Stories.SaveForLater,
    GoodDealWeb.Stories.KeepWishlist,
    GoodDealWeb.Stories.CheckOut,
    GoodDealWeb.Stories.EditOrder,
    GoodDealWeb.Stories.BrowseCatalog,
    GoodDealWeb.Stories.SubmitOrder
  ]

  test "every story wires each port of its parts, and nothing else" do
    for story <- @stories,
        do: assert({story, Wiring.gaps(story)} == {story, %{unwired: [], unknown: []}})
  end

  test "every story has an input clause for each input port it declares, and no other" do
    for story <- @stories,
        do: assert({story, Wiring.input_gaps(story)} == {story, %{unhandled: [], unknown: []}})
  end

  test "every event a story's views fire is declared and handled by that story, and nothing else" do
    for story <- @stories,
        do:
          assert(
            {story, Wiring.event_gaps(story)} ==
              {story, %{unhandled: [], undeclared: [], unused: []}}
          )
  end

  test "no two stories on a page claim the same event" do
    for page <- [GoodDealWeb.CartLive.Show, GoodDealWeb.PortalLive.Show] do
      events =
        for {_, part} <- page.parts(),
            function_exported?(part, :events, 0),
            e <- part.events(),
            do: e

      assert events -- Enum.uniq(events) == []
    end
  end

  @tag :tmp_dir
  test "a story missing an input clause, or wiring a port its parts don't have, is caught", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "gappy.ex")

    File.write!(path, """
    defmodule WiringTest.Part do
      def ports, do: %{in: [], out: [done: :item]}
    end

    defmodule WiringTest.Gappy do
      def parts, do: %{part: WiringTest.Part}
      def ports, do: %{in: [go: :event, stop: :event], out: []}
      def input(s, :go, _, _out), do: s
      def input(s, :jump, _, _out), do: s
      defp wire(s, :part, {:gone, _}, _out), do: s
      def touch(s), do: wire(s, :part, {:gone, nil}, nil)
    end
    """)

    Code.compile_file(path)
    assert Wiring.input_gaps(WiringTest.Gappy) == %{unhandled: [:stop], unknown: [:jump]}
    assert Wiring.gaps(WiringTest.Gappy) == %{unwired: [part: :done], unknown: [part: :gone]}
  end

  test "opting in to the compile-time check fails the build on a gap" do
    source = """
    defmodule WiringTest.Feature do
      def ports, do: %{in: [], out: [rows: :row_change, gone: :item]}
    end

    defmodule WiringTest.Page do
      use GoodDealWeb.Paradigms.Wiring
      @parts %{f: WiringTest.Feature}
      def parts, do: @parts
      defp wire(s, :f, {:rows, _}), do: s
      def touch(s), do: wire(s, :f, {:rows, nil})
    end
    """

    error = assert_raise CompileError, fn -> Code.compile_string(source) end
    assert Exception.message(error) =~ "unwired: [f: :gone]"
  end
end

defmodule GoodDealWeb.DrawingTest do
  use ExUnit.Case, async: true

  test "the cart page's diagram is drawn from its wire/3 clauses" do
    chart = GoodDealWeb.Paradigms.Drawing.mermaid(GoodDealWeb.CartLive.Show)
    assert chart =~ ~s(edit_cart -->|"removed → capture"| undo)
    assert chart =~ ~s(wishlist -->|"taken → add_product"| edit_cart)
    assert chart =~ ~s(payment -->|"done → succeeded"| check_out)
    assert chart =~ ~s(timer_undo -->|"fired → expire"| undo)
  end

  test "a story's diagram is drawn from its handle_event/4, input/4 and wire/4 clauses" do
    chart = GoodDealWeb.Paradigms.Drawing.mermaid_story(GoodDealWeb.Stories.EditCart)
    assert chart =~ ~s(ev_apply_promo[/"apply_promo"/] -->|"apply_promo → enter"| promo)
    assert chart =~ ~s(lines -->|"contents → contents"| totals)

    assert chart =~
             ~s(in_add_product((add_product\)\) -->|"add_product via AddLine.run → receive"| lines)

    assert chart =~ ~s(totals -->|"summary → summary"| out_summary[["summary"]])
  end
end
