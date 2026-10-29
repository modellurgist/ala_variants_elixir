defmodule GoodDealWeb.Paradigms.LiveTest do
  use GoodDealWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias GoodDealWeb.Paradigms.ChangeFeed

  defmodule Page do
    use Phoenix.LiveView

    def mount(_params, %{"topic" => topic}, socket) do
      {:ok,
       socket
       |> assign(got: [], topic: topic)
       |> ChangeFeed.mount([topic: topic, facts: [:stock]], &wire/2)}
    end

    def handle_info(message, socket),
      do: {:noreply, assign(socket, got: socket.assigns.got ++ [{:page, message}])}

    def render(assigns), do: ~H"<pre>{inspect(@got)}</pre>"

    defp wire(socket, output), do: assign(socket, got: socket.assigns.got ++ [output])
  end

  defp open(conn) do
    topic = "change-feed-test-#{System.unique_integer([:positive])}"
    {:ok, lv, _} = live_isolated(conn, Page, session: %{"topic" => topic})
    {lv, topic}
  end

  defp got(lv), do: :sys.get_state(lv.pid).socket.assigns.got

  test "a product's facts are keyed by its id" do
    product = %{id: 7, stock: 3, name: "Widget"}
    assert ChangeFeed.facts(product) == [product: product, stock: %{product_id: 7, stock: 3}]
  end

  test "publishing sends each configured fact out of a feed listening for it", %{conn: conn} do
    {lv, topic} = open(conn)
    product = %{id: 7, stock: 0}

    assert ChangeFeed.publish([topic: topic, facts: [:product, :stock]], product) == product
    assert got(lv) == [stock: %{product_id: 7, stock: 0}]
  end

  test "a feed ignores other topics and leaves the page's own messages to it", %{conn: conn} do
    {lv, _topic} = open(conn)
    ChangeFeed.publish([topic: "elsewhere", facts: [:stock]], %{id: 7, stock: 0})
    send(lv.pid, :tick)

    assert got(lv) == [page: :tick]
  end
end
