defmodule GoodDealWeb.Paradigms.LiveTest do
  use ExUnit.Case, async: true

  alias GoodDeal.Domain.ProductFacts
  alias GoodDealWeb.Paradigms.ChangeFeed

  defp feed_for(facts),
    do: %ChangeFeed{
      topic: "change_feed_test_#{System.unique_integer()}",
      format: ProductFacts,
      facts: facts
    }

  # stands in for the page's wiring: records each output it is sent
  defp out, do: fn socket, output -> Map.update!(socket, :sent, &(&1 ++ [output])) end

  @socket %{sent: []}

  describe "deliver/4, the page's handle_info hook" do
    test "a fact of a kind the page listens to goes out on the port of that kind" do
      feed = feed_for([:stock])
      fact = %{product_id: 7, stock: 0}

      assert ChangeFeed.deliver({ChangeFeed, feed.topic, :stock, fact}, feed, @socket, out()) ==
               {:halt, %{sent: [stock: fact]}}
    end

    test "a fact of a kind the page doesn't listen to is taken and dropped" do
      feed = feed_for([:stock])

      assert ChangeFeed.deliver(
               {ChangeFeed, feed.topic, :product, %{id: 7}},
               feed,
               @socket,
               out()
             ) ==
               {:halt, @socket}
    end

    test "a fact on another topic, or any other message, passes on to the page" do
      feed = feed_for([:stock])

      assert ChangeFeed.deliver({ChangeFeed, "elsewhere", :stock, %{}}, feed, @socket, out()) ==
               {:cont, @socket}

      assert ChangeFeed.deliver({:timer, :undo, nil}, feed, @socket, out()) == {:cont, @socket}
    end
  end

  describe "publish/2" do
    test "sends a changed record as each fact kind the instance names, built by its format" do
      feed = feed_for([:product, :stock])
      Phoenix.PubSub.subscribe(GoodDeal.PubSub, feed.topic)
      product = %{id: 7, stock: 3, name: "Widget"}

      assert ChangeFeed.publish(feed, product) == :ok

      topic = feed.topic
      assert_received {ChangeFeed, ^topic, :product, ^product}
      assert_received {ChangeFeed, ^topic, :stock, %{product_id: 7, stock: 3}}
    end

    test "a publisher and a subscriber of the same topic meet: the output is what was published" do
      feed = feed_for([:stock])
      Phoenix.PubSub.subscribe(GoodDeal.PubSub, feed.topic)
      ChangeFeed.publish(feed, %{id: 7, stock: 0})
      assert_received message

      assert ChangeFeed.deliver(message, feed, @socket, out()) ==
               {:halt, %{sent: [stock: %{product_id: 7, stock: 0}]}}
    end
  end

  test "the format declares one output port per fact kind, and carries only the id with the stock" do
    product = %{id: 7, stock: 3, name: "x"}
    facts = ProductFacts.facts(product)
    assert Keyword.keys(facts) == Keyword.keys(ProductFacts.ports().out)
    assert facts[:stock] == %{product_id: 7, stock: 3}
    assert facts[:product] == product
  end
end
