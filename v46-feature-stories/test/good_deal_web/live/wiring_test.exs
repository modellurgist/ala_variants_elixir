defmodule GoodDealWeb.WiringTest do
  use ExUnit.Case, async: true
  alias GoodDealWeb.Paradigms.{Steps, Wiring}

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

  test "every story wires each part port, handles each input, and each event its view emits" do
    for story <- @stories,
        do:
          assert(
            Wiring.story_gaps(story) |> Map.values() |> Enum.all?(&(&1 == [])),
            inspect({story, Wiring.story_gaps(story)})
          )
  end

  test "a story's gaps name what's missing and what's undeclared" do
    assert Wiring.story_gaps(GoodDealWeb.GappyStory) == %{
             unwired: [undo: :restored, undo: :expired],
             unknown: [],
             inputs_unhandled: [:expire],
             inputs_undeclared: [:surprise],
             events_unhandled: ["never_handled"],
             events_undeclared: []
           }
  end

  test "no two stories on a page claim the same event" do
    assert Wiring.event_clashes(GoodDealWeb.CartLive.Show) == []
    assert Wiring.event_clashes(GoodDealWeb.PortalLive.Show) == []
  end

  test "opting in to the compile-time check fails the build on a gap" do
    source = """
    defmodule WiringTest.Feature do
      def ports, do: %{in: [], out: [rows: :row_change, gone: :item]}
    end

    defmodule WiringTest.Page do
      use GoodDealWeb.Paradigms.Wiring
      @features %{f: WiringTest.Feature}
      def features, do: @features
      defp wire(s, :f, {:rows, _}), do: s
      def touch(s), do: wire(s, :f, {:rows, nil})
    end
    """

    error = assert_raise CompileError, fn -> Code.compile_string(source) end
    assert Exception.message(error) =~ "unwired: [f: :gone]"
  end

  test "a clause naming an instance the page didn't configure fails with its name" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, instances: %{}}}

    assert_raise ArgumentError, ~r/no configured instance :charge/, fn ->
      Steps.call(socket, {:charge, fn _instance, _payload -> :ok end}, nil)
    end
  end
end

defmodule GoodDealWeb.DrawingTest do
  use ExUnit.Case, async: true
  alias GoodDealWeb.Paradigms.Drawing

  test "the cart page's diagram shows its stories and the links between them" do
    chart = Drawing.mermaid(GoodDealWeb.CartLive.Show)
    assert chart =~ ~s(edit_cart -->|"removed → capture"| undo)
    assert chart =~ ~s(check_out -->|"pay_requested → request_checkout"| edit_cart)
  end

  test "a story's diagram shows its inputs, parts and outputs" do
    chart = Drawing.mermaid_story(GoodDealWeb.Stories.KeepWishlist)
    assert chart =~ "in_toggle((toggle)) -->|\"toggle → toggle\"| wishlist"
    assert chart =~ "wishlist -->|\"taken via add_line\"| out_added_to_cart((added_to_cart))"
  end
end
