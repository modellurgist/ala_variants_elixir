defmodule ZeroCoupled.EffectsTest do
  use ExUnit.Case, async: true

  alias ZeroCoupled.Effects

  test "constructors build the matching structs" do
    assert Effects.flash(:info, "hi") == %Effects.Flash{level: :info, message: "hi"}
    assert Effects.push("e", %{a: 1}) == %Effects.Push{event: "e", payload: %{a: 1}}
    assert Effects.stream_insert(:cart_items, :x) == %Effects.StreamInsert{name: :cart_items, item: :x, at: -1}
    assert Effects.stream_delete(:cart_items, :x) == %Effects.StreamDelete{name: :cart_items, item: :x}
    assert Effects.patch("/p") == %Effects.Patch{to: "/p"}
    assert Effects.navigate("/n") == %Effects.Navigate{to: "/n"}
    assert Effects.redirect_external("u") == %Effects.Redirect{external: "u"}
    assert Effects.start_timer(:undo, 5, :msg) == %Effects.StartTimer{name: :undo, after_ms: 5, message: :msg}
    assert Effects.cancel_timer(:undo) == %Effects.CancelTimer{name: :undo}
    assert Effects.persist_quantity(1, 2, 3) == %Effects.Persist{op: :update_quantity, cart_id: 1, item_id: 2, quantity: 3}
    assert Effects.persist_remove(1, 2) == %Effects.Persist{op: :remove, cart_id: 1, item_id: 2}
    assert Effects.start_checkout([], %{}) == %Effects.StartCheckout{line_items: [], metadata: %{}}
  end
end
