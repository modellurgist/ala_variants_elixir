defmodule ZeroCoupled.Features.SavedItemsTest do
  use ExUnit.Case, async: true

  import ZeroCoupled.CartFixtures
  alias ZeroCoupled.Features.SavedItems

  test "save adds an item and counts it" do
    saved = SavedItems.init([]) |> SavedItems.save(line_item(1))
    assert SavedItems.count(saved) == 1
    assert [%{id: 1}] = SavedItems.list(saved)
  end

  test "save is idempotent by id" do
    saved = SavedItems.init([]) |> SavedItems.save(line_item(1)) |> SavedItems.save(line_item(1))
    assert SavedItems.count(saved) == 1
  end

  test "take removes and returns an item" do
    saved = SavedItems.init([]) |> SavedItems.save(line_item(1)) |> SavedItems.save(line_item(2))
    assert {saved, %{id: 1}} = SavedItems.take(saved, 1)
    assert SavedItems.count(saved) == 1
  end

  test "take of unknown id returns nil" do
    assert {_saved, nil} = SavedItems.take(SavedItems.init([]), 99)
  end
end
