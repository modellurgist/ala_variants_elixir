defmodule GoodDeal.ChangeFeedTest do
  use ExUnit.Case, async: true

  alias GoodDeal.ChangeFeed
  alias Phoenix.LiveView.Socket

  test "a listener receives the facts of the kinds it listens to, and no others" do
    ChangeFeed.listen([:feed_test_level])

    ChangeFeed.publish(:feed_test_level, 7, %{level: 3})
    ChangeFeed.publish(:feed_test_other, 7, %{level: 4})

    assert_receive %ChangeFeed{kind: :feed_test_level, id: 7, values: %{level: 3}}
    refute_receive %ChangeFeed{kind: :feed_test_other}, 20
  end

  test "a fact needs a kind atom and a map of values" do
    assert_raise FunctionClauseError, fn -> ChangeFeed.publish("level", 7, %{}) end
    assert_raise FunctionClauseError, fn -> ChangeFeed.publish(:feed_test_level, 7, 3) end
  end

  test "dispatch hands a declared fact to its handler and halts" do
    handlers = %{feed_test_level: fn fact, socket -> {socket, fact.id, fact.values} end}
    fact = %ChangeFeed{kind: :feed_test_level, id: 7, values: %{level: 3}}

    assert ChangeFeed.dispatch(handlers, fact, :socket) == {:halt, {:socket, 7, %{level: 3}}}
  end

  test "dispatch passes on any other message, including an undeclared kind" do
    handlers = %{feed_test_level: fn _fact, _socket -> flunk("not this handler") end}
    other = %ChangeFeed{kind: :feed_test_other, id: 7, values: %{}}

    assert ChangeFeed.dispatch(handlers, other, :socket) == {:cont, :socket}
    assert ChangeFeed.dispatch(handlers, {:undo_expired, 1}, :socket) == {:cont, :socket}
  end

  test "a disconnected socket is returned unchanged and listens to nothing" do
    socket = %Socket{}
    assert ChangeFeed.subscribe(socket, %{feed_test_quiet: fn _f, s -> s end}) == socket

    ChangeFeed.publish(:feed_test_quiet, 1, %{})
    refute_receive %ChangeFeed{}, 20
  end
end
