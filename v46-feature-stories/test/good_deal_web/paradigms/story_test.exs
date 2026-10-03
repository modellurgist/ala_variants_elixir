defmodule GoodDealWeb.Paradigms.StoryTest do
  use ExUnit.Case, async: true
  alias GoodDealWeb.Paradigms.Story
  alias GoodDealWeb.Stories.UndoRemoval

  defp socket(assigns), do: %Phoenix.LiveView.Socket{assigns: Map.put(assigns, :__changed__, %{})}

  test "a story's timer reports to its own input port" do
    s = socket(%{undo: UndoRemoval.new(window_ms: 1)})
    Story.start_timer(s, :undo, :undo, %{id: 7})
    assert_receive {:story_input, :undo, :expire, %{id: 7}}
  end

  test "a task's outcome goes to the input named for ok or for error" do
    test = self()
    inputs = %{module: __MODULE__.Echo}
    s = socket(%{echo: struct(Story, inputs), test: test})

    Story.async_result(s, {:story_async, :echo, :won, :lost}, {:ok, {:ok, 1}})
    Story.async_result(s, {:story_async, :echo, :won, :lost}, {:ok, {:error, :no}})
    Story.async_result(s, {:story_async, :echo, :won, :lost}, {:exit, :boom})

    assert_received {:won, 1}
    assert_received {:lost, :no}
    assert_received {:lost, :boom}
  end

  defmodule Echo do
    def input(s, :echo, port, payload) do
      send(s.assigns.test, {port, payload})
      s
    end
  end
end
