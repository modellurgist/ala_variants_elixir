defmodule GoodDealWeb.Paradigms.LiveTest do
  use ExUnit.Case, async: true

  alias GoodDealWeb.Paradigms.{ChangeFeed, Wiring}

  defmodule Part do
    def ports, do: %{in: [], out: [done: :x, note: :x]}
  end

  test "a feed declares one output port per fact kind it was configured with" do
    assert ChangeFeed.ports(ChangeFeed.new("t", [:stock, :product])) ==
             %{in: [deliver: :fact], out: [stock: :fact, product: :fact]}

    assert ChangeFeed.ports(ChangeFeed.new("t")).out == []
  end

  test "a feed passes on the facts it listens for and drops the rest" do
    feed = ChangeFeed.new("t", [:stock])

    assert ChangeFeed.deliver(feed, {:stock, {7, 0}}) == {feed, [stock: {7, 0}]}
    assert ChangeFeed.deliver(feed, {:product, 7}) == {feed, []}
  end

  test "a publisher sends a fact, an identity with at most one value, to its topic only" do
    topic = "change-feed-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(GoodDeal.PubSub, topic)

    ChangeFeed.publish(ChangeFeed.new(topic), :stock, 7, 0)
    ChangeFeed.publish(ChangeFeed.new(topic), :product, 7)
    ChangeFeed.publish(ChangeFeed.new("#{topic}-other"), :product, 8)

    assert_receive {ChangeFeed, ^topic, {:stock, {7, 0}}}
    assert_receive {ChangeFeed, ^topic, {:product, 7}}
    refute_receive {ChangeFeed, _, {:product, 8}}
  end

  test "a configured feed's ports count in a page's wiring check" do
    features = %{feed: ChangeFeed.new("t", [:stock]), part: Part}

    assert Enum.sort(Wiring.declared(features)) ==
             [feed: :stock, part: :done, part: :note]
  end
end
