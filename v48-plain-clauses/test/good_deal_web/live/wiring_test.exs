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

  test "the cart page's diagram is drawn from its wire/3 clauses" do
    chart = GoodDealWeb.Paradigms.Drawing.mermaid(GoodDealWeb.CartLive.Show)
    assert chart =~ ~s(cart -->|"removed → capture"| undo)
    assert chart =~ ~s(wishlist -->|"taken via add_line → receive"| cart)
    assert chart =~ ~s(payment -->|"done → succeeded"| checkout)
    assert chart =~ ~s(checkout -.->|"ready_to_pay"| payment["task charge"])
  end
end
