defmodule ZeroCoupledWeb.PortalPageTest do
  @moduledoc """
  Composed-page tests for the D6 second consumer: intents + manifest
  reactions + effects as data, no Phoenix process, no DB — the same pure
  surface the cart page's tests use, now proving the shared catalog
  (aggregate, undo feature, flows machinery, contracts) composes into a
  second page.
  """
  use ExUnit.Case, async: true

  import ZeroCoupled.CartFixtures

  alias ZeroCoupledWeb.PortalPage
  alias ZeroCoupledWeb.PortalPage.Generated
  alias ZeroCoupled.Effects
  alias ZeroCoupled.Features.{OrderLines, PortalSubmit, Undo}
  alias ZeroCoupled.Foundation.Broadcast.Facts, as: BroadcastFacts

  defp session(items \\ [line_item(1, amount: 10_000, quantity: 2)]) do
    PortalPage.Session.new(cart_id: 1, items: items, products: [product(10), product(20)])
  end

  defp has?(effects, pred), do: Enum.any?(effects, pred)

  test "the portal manifest is closed and well-typed" do
    assert :ok = ZeroCoupledWeb.PageCheck.verify(ZeroCoupledWeb.PortalPage)
  end

  describe "order lines (the Cart aggregate reused)" do
    test "set_line_quantity applies an absolute quantity and persists it" do
      {s, effects} = PortalPage.run_intent(session(), :set_line_quantity, %{item_id: 1, quantity: 7})

      assert Enum.find(s.order.items, &(&1.id == 1)).quantity == 7
      assert has?(effects, &match?(%Effects.Persist{op: :update_quantity, quantity: 7}, &1))
      assert has?(effects, &match?(%Effects.StreamInsert{name: :order_lines}, &1))
    end

    test "volume tier reprices automatically across a tier boundary" do
      # 2 × $100 = $200 → below the $500 tier.
      s = session()
      assert s.order.discount == Money.new(0)

      # 6 × $100 = $600 → 5% tier, applied without any promo code.
      {s, _} = PortalPage.run_intent(s, :set_line_quantity, %{item_id: 1, quantity: 6})
      assert s.order.discount == Money.new(3_000)
      assert OrderLines.render_data(s.order).tier_label == "5% volume discount"

      # 25 × $100 = $2500 → 10% tier.
      {s, _} = PortalPage.run_intent(s, :set_line_quantity, %{item_id: 1, quantity: 25})
      assert s.order.discount == Money.new(25_000)

      # Back below every tier.
      {s, _} = PortalPage.run_intent(s, :set_line_quantity, %{item_id: 1, quantity: 2})
      assert s.order.discount == Money.new(0)
      assert OrderLines.render_data(s.order).tier_label == nil
    end

    test "removing a line captures undo via the translated wire (feature reuse)" do
      {s, effects} = PortalPage.run_intent(session(), :remove_line, %{item_id: 1})

      # The undo feature — reused byte-identical from the cart page — armed
      # itself off OrderLines' own vocabulary (LineRemoved → transform).
      assert Undo.pending?(s.undo)
      assert s.order.items == []
      assert has?(effects, &match?(%Effects.StartTimer{name: :undo}, &1))
      assert has?(effects, &match?(%Effects.StreamDelete{name: :order_lines}, &1))
      # Not persisted yet: removal is final only after the undo window.
      refute has?(effects, &match?(%Effects.Persist{op: :remove}, &1))
    end

    test "undo_remove restores the line and reprices" do
      {s, _} = PortalPage.run_intent(session(), :remove_line, %{item_id: 1})
      {s, effects} = PortalPage.run_intent(s, :undo_remove, %{})

      refute Undo.pending?(s.undo)
      assert Enum.find(s.order.items, &(&1.id == 1))
      assert has?(effects, &match?(%Effects.StreamInsert{name: :order_lines}, &1))
    end

    test "the elapsed undo window persists the removal" do
      {s, _} = PortalPage.run_intent(session(), :remove_line, %{item_id: 1})
      {s, effects} = PortalPage.run_pure(s, &Undo.Intents.undo_expired(&1, 1))

      refute Undo.pending?(s.undo)
      assert has?(effects, &match?(%Effects.Persist{op: :remove, item_id: 1}, &1))
    end
  end

  describe "cross-process facts" do
    test "StockChanged fans out to both the order and the catalog slot" do
      fact = %BroadcastFacts.StockChanged{product_id: 1, stock: 0}
      {s, effects} = PortalPage.run_pure(session(), &Generated.apply_fact(&1, fact))

      assert Enum.find(s.order.items, &(&1.product.id == 1)).product.stock == 0
      assert has?(effects, &match?(%Effects.StreamInsert{name: :order_lines}, &1))

      fact = %BroadcastFacts.StockChanged{product_id: 10, stock: 0}
      {s, effects} = PortalPage.run_pure(s, &Generated.apply_fact(&1, fact))

      assert Enum.find(s.catalog.products, &(&1.id == 10)).stock == 0
      assert has?(effects, &match?(%Effects.StreamInsert{name: :portal_products}, &1))
    end
  end

  describe "the bulk-order flow (V33 channel, second flow)" do
    test "go_review advances along the declared edge and patches the flow URL" do
      {s, effects} = PortalPage.run_intent(session(), :go_review, %{})
      assert s.flow.step == :review
      assert has?(effects, &match?(%Effects.PatchFlow{flow: :bulk_order, step: :review}, &1))
    end

    test "go_review on an empty order flashes instead" do
      empty = PortalPage.Session.new(cart_id: 1, items: [], products: [])
      {s, effects} = PortalPage.run_intent(empty, :go_review, %{})
      assert s.flow.step == :lines
      assert has?(effects, &match?(%Effects.Flash{level: :error}, &1))
    end

    test "validate_po rejects a malformed number and accepts a real one" do
      s = session()
      assert {:error, changeset} = PortalSubmit.Intents.validate_po(s, %{"number" => "nope"})
      refute changeset.valid?
      assert {:ok, po} = PortalSubmit.Intents.validate_po(s, %{"number" => "PO-2026"})
      assert po.number == "PO-2026"
    end

    test "complete_submit lands on :submitted with the order reference" do
      {s, _} = PortalPage.run_intent(session(), :go_review, %{})
      {:ok, po} = PortalSubmit.Intents.validate_po(s, %{"number" => "PO-2026"})
      {s, effects} = PortalPage.run_pure(s, &PortalSubmit.Intents.complete_submit(&1, po, 42))

      assert s.flow.step == :submitted
      assert PortalSubmit.render_data(s.flow) == %{step: :submitted, po_number: "PO-2026", order_id: 42}
      assert has?(effects, &match?(%Effects.PatchFlow{flow: :bulk_order, step: :submitted}, &1))
    end

    test "URL goto_step honors only the backward edge" do
      {s, _} = PortalPage.run_intent(session(), :go_review, %{})

      {back, []} = PortalPage.run_pure(s, &PortalSubmit.Intents.goto_step(&1, :lines))
      assert back.flow.step == :lines

      # Forward jump to review from lines: ignored.
      {still, []} = PortalPage.run_pure(back, &PortalSubmit.Intents.goto_step(&1, :review))
      assert still.flow.step == :lines
    end
  end
end
