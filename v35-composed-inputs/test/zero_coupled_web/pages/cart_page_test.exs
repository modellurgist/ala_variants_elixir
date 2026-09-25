defmodule ZeroCoupledWeb.CartPageTest do
  @moduledoc """
  The composed page tested **purely**: intents run through the
  manifest's compiled reactions via `run_intent/3` / `run_pure/2` —
  no Phoenix process, no database. This replaces V28's session_test
  and additionally covers the manifest machinery itself.
  """
  use ExUnit.Case, async: true

  import ZeroCoupled.CartFixtures

  alias ZeroCoupledWeb.CartPage
  alias ZeroCoupledWeb.CartPage.Generated
  alias ZeroCoupled.Effects
  alias ZeroCoupled.Features.{CartItems, Undo, SavedItems, Wishlist, CheckoutFlow}
  alias ZeroCoupled.Foundation.Broadcast.Facts, as: BroadcastFacts

  defp session do
    CartPage.Session.new(
      cart_id: 1,
      items: [
        line_item(1, product_id: 10, amount: 1000, quantity: 1, stock: 10),
        line_item(2, product_id: 20, amount: 2500, quantity: 1, stock: 5)
      ]
    )
  end

  defp has?(effects, pred), do: Enum.any?(effects, pred)

  describe "Session.new/1" do
    test "builds every slot from its feature's init/1" do
      s = session()
      assert s.cart.cart_id == 1
      assert length(s.cart.items) == 2
      refute Undo.pending?(s.undo)
      assert SavedItems.count(s.saved) == 0
      assert Wishlist.count(s.wishlist) == 0
      assert s.checkout.step == :address
      assert s.ui.active_tab == :items
    end
  end

  describe "cart intents" do
    test "update_quantity updates the cart and emits stream + persist effects" do
      {s, effects} = CartPage.run_intent(session(), :update_quantity, %{item_id: 1, delta: 1})

      assert Enum.find(s.cart.items, &(&1.id == 1)).quantity == 2
      assert has?(effects, &match?(%Effects.StreamInsert{name: :cart_items}, &1))
      assert has?(effects, &match?(%Effects.Persist{op: :update_quantity, quantity: 2}, &1))
    end

    test "update_quantity on an unknown item is a no-op" do
      assert {_s, []} = CartPage.run_intent(session(), :update_quantity, %{item_id: 999, delta: 1})
    end

    test "toggle_gift_wrap recomputes totals" do
      {s, effects} = CartPage.run_intent(session(), :toggle_gift_wrap, %{item_id: 1})
      assert s.cart.gift_wrap_total == Money.new(299)
      assert has?(effects, &match?(%Effects.StreamInsert{name: :cart_items}, &1))
    end

    test "select_shipping updates the method" do
      {s, []} = CartPage.run_intent(session(), :select_shipping, %{method: :overnight})
      assert s.cart.shipping_method == :overnight
    end
  end

  describe "remove + undo (fact :item_removed → Undo reaction)" do
    test "remove_item updates the cart AND arms undo via the wired reaction" do
      {s, effects} = CartPage.run_intent(session(), :remove_item, %{item_id: 1})

      refute Enum.any?(s.cart.items, &(&1.id == 1))
      # the reaction (another feature's slot) ran through the manifest:
      assert Undo.pending?(s.undo)
      assert has?(effects, &match?(%Effects.StreamDelete{name: :cart_items}, &1))
      assert has?(effects, &match?(%Effects.Push{event: "item-removed"}, &1))
      assert has?(effects, &match?(%Effects.StartTimer{name: :undo}, &1))
      assert has?(effects, &match?(%Effects.Flash{level: :info}, &1))
    end

    test "undo_remove restores the item via fact :item_restored → cart reaction" do
      {s, _} = CartPage.run_intent(session(), :remove_item, %{item_id: 1})
      {s, effects} = CartPage.run_intent(s, :undo_remove, %{})

      assert Enum.any?(s.cart.items, &(&1.id == 1))
      refute Undo.pending?(s.undo)
      assert has?(effects, &match?(%Effects.CancelTimer{name: :undo}, &1))
      assert has?(effects, &match?(%Effects.StreamInsert{name: :cart_items}, &1))
    end

    test "undo_remove with nothing pending is a no-op" do
      assert {_s, []} = CartPage.run_intent(session(), :undo_remove, %{})
    end

    test "undo_expired persists the removal via fact :removal_final → cart reaction" do
      {s, _} = CartPage.run_intent(session(), :remove_item, %{item_id: 1})
      {s, effects} = CartPage.run_pure(s, &Undo.Intents.undo_expired(&1, 1))

      refute Undo.pending?(s.undo)
      assert has?(effects, &match?(%Effects.Persist{op: :remove, item_id: 1, cart_id: 1}, &1))
    end

    test "undo_expired with nothing pending is a no-op" do
      assert {_s, []} = CartPage.run_pure(session(), &Undo.Intents.undo_expired(&1, 1))
    end
  end

  describe "save for later (facts :item_saved / :moved_to_cart)" do
    test "save_for_later moves the item cart → saved through the wiring" do
      {s, effects} = CartPage.run_intent(session(), :save_for_later, %{item_id: 1})

      refute Enum.any?(s.cart.items, &(&1.id == 1))
      assert SavedItems.count(s.saved) == 1
      assert has?(effects, &match?(%Effects.StreamDelete{name: :cart_items}, &1))
      assert has?(effects, &match?(%Effects.StreamInsert{name: :saved_items}, &1))
    end

    test "move_to_cart brings it back through the wiring" do
      {s, _} = CartPage.run_intent(session(), :save_for_later, %{item_id: 1})
      {s, effects} = CartPage.run_intent(s, :move_to_cart, %{item_id: 1})

      assert Enum.any?(s.cart.items, &(&1.id == 1))
      assert SavedItems.count(s.saved) == 0
      assert has?(effects, &match?(%Effects.StreamDelete{name: :saved_items}, &1))
      assert has?(effects, &match?(%Effects.StreamInsert{name: :cart_items}, &1))
    end
  end

  describe "promo (facts → PageUI reactions)" do
    test "valid promo applies discount and clears the ui error" do
      {s, _} = CartPage.run_intent(session(), :apply_promo, %{code: "NOPE"})
      assert s.ui.promo_error == "Invalid promo code"

      {s, effects} = CartPage.run_intent(s, :apply_promo, %{code: "SAVE10"})
      assert s.cart.promo_code == "SAVE10"
      assert s.ui.promo_error == nil
      assert has?(effects, &match?(%Effects.Flash{level: :info}, &1))
    end

    test "invalid promo sets the ui error via the wired reaction" do
      {s, effects} = CartPage.run_intent(session(), :apply_promo, %{code: "BOGUS"})
      assert s.ui.promo_error == "Invalid promo code"
      assert has?(effects, &match?(%Effects.Flash{level: :error}, &1))
    end
  end

  describe "wishlist" do
    # R2 (V35): toggle_wishlist is composition-resolved — the shell finds the
    # cart item and passes it in. The test plays that composition role.
    defp toggle_wl(session, item_id) do
      item = Enum.find(session.cart.items, &(&1.id == item_id))
      CartPage.run_pure(session, &Wishlist.Intents.toggle_wishlist(&1, item))
    end

    test "toggle_wishlist adds the item's product" do
      {s, effects} = toggle_wl(session(), 1)
      assert Wishlist.member?(s.wishlist, 10)
      assert has?(effects, &match?(%Effects.StreamInsert{name: :wishlist_products}, &1))
    end

    test "toggle_wishlist for an unknown item is a no-op" do
      assert {_s, []} = toggle_wl(session(), 999)
    end

    test "remove_wishlist streams a delete" do
      {s, _} = toggle_wl(session(), 1)
      {s, effects} = CartPage.run_intent(s, :remove_wishlist, %{product_id: 10})
      refute Wishlist.member?(s.wishlist, 10)
      assert has?(effects, &match?(%Effects.StreamDelete{name: :wishlist_products}, &1))
    end

    test "add_wishlisted adds the cart line and drops the wishlist entry via the wiring" do
      {s, _} = toggle_wl(session(), 1)
      new_item = line_item(99, product_id: 10, amount: 1000)
      {s, effects} = CartPage.run_pure(s, &CartItems.Intents.add_wishlisted(&1, new_item, 10))

      assert Enum.any?(s.cart.items, &(&1.id == 99))
      refute Wishlist.member?(s.wishlist, 10)
      assert has?(effects, &match?(%Effects.StreamInsert{name: :cart_items}, &1))
      assert has?(effects, &match?(%Effects.StreamDelete{name: :wishlist_products}, &1))
    end
  end

  describe "real-time stock and tabs" do
    # V32 Enhancement B: stock changes arrive as a typed cross-process fact
    # routed through the manifest, exercised here exactly as the page's
    # generic handle_info forwards it.
    test "a StockChanged fact updates the cart item" do
      fact = %BroadcastFacts.StockChanged{product_id: 10, stock: 2}
      {s, effects} = CartPage.run_pure(session(), &Generated.apply_fact(&1, fact))
      assert Enum.find(s.cart.items, &(&1.product.id == 10)).product.stock == 2
      assert has?(effects, &match?(%Effects.StreamInsert{name: :cart_items}, &1))
    end

    test "a StockChanged fact for an absent product is a no-op" do
      fact = %BroadcastFacts.StockChanged{product_id: 999, stock: 0}
      assert {_s, []} = CartPage.run_pure(session(), &Generated.apply_fact(&1, fact))
    end

    test "switch_tab changes only the ui slot; unknown tabs are ignored" do
      {s, []} = CartPage.run_intent(session(), :switch_tab, %{tab: :wishlist})
      assert s.ui.active_tab == :wishlist

      {s, []} = CartPage.run_intent(s, :switch_tab, %{tab: :bogus})
      assert s.ui.active_tab == :wishlist
    end
  end

  describe "checkout flow" do
    @valid %{"name" => "Ada", "line1" => "1 Ave", "city" => "London", "postal_code" => "12345"}

    test "start_checkout patches to the flow's initial step" do
      {_s, effects} = CartPage.run_intent(session(), :start_checkout, %{})
      # V33: the pure core names {flow, step}; the URL is web knowledge,
      # resolved by the interpreter via the generated flow_path/2.
      assert has?(effects, &match?(%Effects.PatchFlow{flow: :checkout, step: :address}, &1))
    end

    test "start_checkout on an empty cart flashes an error" do
      {_s, effects} = CartPage.run_intent(CartPage.Session.new(cart_id: 1), :start_checkout, %{})
      assert has?(effects, &match?(%Effects.Flash{level: :error}, &1))
    end

    test "submit_address advances to payment; edit_address goes back" do
      assert {:ok, s, effects} = CheckoutFlow.Intents.submit_address(session(), @valid)
      assert s.checkout.step == :payment
      assert has?(effects, &match?(%Effects.PatchFlow{flow: :checkout, step: :payment}, &1))

      {s, effects} = CartPage.run_intent(s, :edit_address, %{})
      assert s.checkout.step == :address
      assert has?(effects, &match?(%Effects.PatchFlow{flow: :checkout, step: :address}, &1))
    end

    test "URL goto_step honors only the backward edge (feature policy)" do
      assert {:ok, s, _} = CheckoutFlow.Intents.submit_address(session(), @valid)

      # Back to address: allowed (the :edit_address edge).
      {s2, []} = CartPage.run_pure(s, &CheckoutFlow.Intents.goto_step(&1, :address))
      assert s2.checkout.step == :address

      # Forward jump from address to payment: ignored (skips validation).
      {s3, []} = CartPage.run_pure(s2, &CheckoutFlow.Intents.goto_step(&1, :payment))
      assert s3.checkout.step == :address
    end

    test "submit_address returns a changeset on invalid input" do
      assert {:error, changeset} =
               CheckoutFlow.Intents.submit_address(session(), %{@valid | "postal_code" => "x"})

      refute changeset.valid?
    end

    test "pay validates stock and starts async checkout" do
      # pay is edge-gated by the flow table: it must be reached from the
      # payment (or error) step, so get there through the real transition.
      assert {:ok, s, _} = CheckoutFlow.Intents.submit_address(session(), @valid)
      {s, effects} = CartPage.run_pure(s, &CheckoutFlow.Intents.pay(&1, %{10 => 10, 20 => 10}))
      assert s.checkout.step == :processing
      assert has?(effects, &match?(%Effects.StartCheckout{}, &1))
    end

    test "pay from a step with no :pay edge is a no-op" do
      assert {_s, []} = CartPage.run_pure(session(), &CheckoutFlow.Intents.pay(&1, %{10 => 10, 20 => 10}))
    end

    test "pay flashes when stock is insufficient" do
      {s, effects} = CartPage.run_pure(session(), &CheckoutFlow.Intents.pay(&1, %{10 => 0, 20 => 0}))
      assert s.checkout.step != :processing
      assert has?(effects, &match?(%Effects.Flash{level: :error}, &1))
    end

    test "checkout_succeeded redirects; checkout_failed flags the error" do
      {s, effects} = CartPage.run_pure(session(), &CheckoutFlow.Intents.checkout_succeeded(&1, "https://pay/x"))
      assert s.checkout.step == :complete
      assert has?(effects, &match?(%Effects.Redirect{external: "https://pay/x"}, &1))

      {s, effects} = CartPage.run_pure(session(), &CheckoutFlow.Intents.checkout_failed/1)
      assert s.checkout.step == :error
      assert has?(effects, &match?(%Effects.Flash{level: :error}, &1))
    end
  end

  describe "per-slot change tracking (structural sharing)" do
    test "an intent leaves untouched slots as the same term, so slot assigns no-op" do
      s1 = session()
      {s2, _effects} = CartPage.run_intent(s1, :update_quantity, %{item_id: 1, delta: 1})

      # The cart slot changed…
      refute :erts_debug.same(s1.cart, s2.cart)
      # …but every untouched slot is literally the same heap term, which is
      # what makes the generated per-slot `assign/3` calls equality-no-ops
      # and lets LiveView skip those features' template regions entirely.
      assert :erts_debug.same(s1.undo, s2.undo)
      assert :erts_debug.same(s1.saved, s2.saved)
      assert :erts_debug.same(s1.wishlist, s2.wishlist)
      assert :erts_debug.same(s1.checkout, s2.checkout)
      assert :erts_debug.same(s1.ui, s2.ui)
    end

    test "render_data (@cart) is recomputed only when the cart slot changes (V30 gate)" do
      socket =
        Generated.mount_session(%Phoenix.LiveView.Socket{},
          cart_id: 1,
          items: [line_item(1, product_id: 10, amount: 1000, quantity: 1, stock: 10)]
        )

      cart_render = socket.assigns.cart
      base = socket.assigns.session

      # A non-cart event (switch_tab writes only :ui): the gate skips the
      # render_data recompute, so @cart is the *same term* as before.
      {s_ui, _} = CartPage.run_intent(base, :switch_tab, %{tab: :wishlist})
      assert :erts_debug.same(cart_render, Generated.put_session(socket, s_ui).assigns.cart)

      # A cart event: the gate fires and @cart is a fresh term.
      {s_cart, _} = CartPage.run_intent(base, :update_quantity, %{item_id: 1, delta: 1})
      refute :erts_debug.same(cart_render, Generated.put_session(socket, s_cart).assigns.cart)
    end
  end

  describe "the manifest machinery" do
    test "the manifest is closed and well-typed" do
      assert :ok = ZeroCoupledWeb.PageCheck.verify(CartPage)
    end

    test "an undeclared fact raises loudly" do
      assert_raise ArgumentError, ~r/undeclared fact/, fn ->
        CartPage.run_pure(session(), fn s -> {s, [], [{:no_such_fact, %{}}]} end)
      end
    end

    test "an unknown intent name raises loudly" do
      assert_raise ArgumentError, ~r/unknown intent/, fn ->
        CartPage.run_intent(session(), :no_such_intent, %{})
      end
    end

    test "cast_params casts by the declared spec (dasherized keys)" do
      assert %{item_id: 7, delta: -1} =
               ZeroCoupledWeb.PageCheck.cast_params(
                 %{"item-id" => "7", "delta" => "-1"},
                 item_id: :int,
                 delta: :int
               )

      assert %{tab: :saved} = ZeroCoupledWeb.PageCheck.cast_params(%{"tab" => "saved"}, tab: :atom)
      assert %{code: "X"} = ZeroCoupledWeb.PageCheck.cast_params(%{"code" => "X"}, code: :string)
    end

    test "the committed generated.ex matches a fresh generation (what `zc.gen --check` enforces)" do
      fresh = ZeroCoupled.Gen.PageGenerator.generate(CartPage)
      path = ZeroCoupled.Gen.PageGenerator.generated_path(CartPage)
      assert File.read!(path) == fresh, "generated.ex is stale — run `mix zc.gen`"
    end

    test "the generated glue is the code you'd write by hand (committed source)" do
      src = ZeroCoupled.Gen.PageGenerator.generate(CartPage)
      assert src =~ ~s|def page_event("remove_item", params, socket, run)|
      # typed facts: struct-matched clause heads + default projection
      assert src =~ "Facts.ItemRemoved{} = fact"
      assert src =~ "Map.from_struct(fact)"
      # the one transform wire is spliced inline
      assert src =~ "saved_item"
      assert src =~ "ZeroCoupled.Features.Undo.Intents.capture_removed"
      assert src =~ "defmodule ZeroCoupledWeb.CartPage.Session"
    end

    test "__manifest__/0 lists features, typed-fact reactions, views and intents" do
      m = CartPage.__manifest__()
      assert Enum.any?(m.features, &match?({:cart, ZeroCoupled.Features.CartItems, _}, &1))

      assert Enum.any?(
               m.reactions,
               &match?({ZeroCoupled.Features.CartItems.Facts.ItemRemoved, [_ | _]}, &1)
             )

      # the MovedToCart wire records its transform
      assert {ZeroCoupled.Features.SavedItems.Facts.MovedToCart, [{:cart, _, :receive_item, transform: true}]} =
               Enum.find(m.reactions, &match?({ZeroCoupled.Features.SavedItems.Facts.MovedToCart, _}, &1))

      assert Enum.any?(m.action_views, &match?({:checkout, _}, &1))
      assert Enum.any?(m.intents, &match?({:remove_item, :cart, _, _}, &1))
    end
  end
end
