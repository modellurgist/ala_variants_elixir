defmodule ZeroCoupled.Features.WishlistTest do
  use ExUnit.Case, async: true

  import ZeroCoupled.CartFixtures
  alias ZeroCoupled.Features.Wishlist

  test "toggle adds then removes a product" do
    p = product(1)
    {wl, :added} = Wishlist.toggle(Wishlist.init([]), p)
    assert Wishlist.member?(wl, 1)
    assert Wishlist.count(wl) == 1

    {wl, :removed} = Wishlist.toggle(wl, p)
    refute Wishlist.member?(wl, 1)
    assert Wishlist.count(wl) == 0
  end

  test "take removes and returns a product" do
    wl = Wishlist.init([]) |> Wishlist.toggle(product(1)) |> elem(0)
    assert {wl, %{id: 1}} = Wishlist.take(wl, 1)
    refute Wishlist.member?(wl, 1)
  end

  test "take of unknown id returns nil" do
    assert {_wl, nil} = Wishlist.take(Wishlist.init([]), 99)
  end

  test "remove is a no-op for unknown id" do
    wl = Wishlist.init([]) |> Wishlist.toggle(product(1)) |> elem(0)
    assert Wishlist.remove(wl, 99) == wl
  end

  test "list returns the products in insertion order" do
    wl = Wishlist.init([])
    {wl, _} = Wishlist.toggle(wl, product(1))
    {wl, _} = Wishlist.toggle(wl, product(2))
    assert [%{id: 1}, %{id: 2}] = Wishlist.list(wl)
  end
end
