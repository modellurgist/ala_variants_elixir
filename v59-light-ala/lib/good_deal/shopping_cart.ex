defmodule GoodDeal.ShoppingCart do
  @moduledoc """
  The ShoppingCart context: carts, cart items, saved-for-later and the wishlist.
  """

  import Ecto.Query, warn: false
  alias GoodDeal.Repo

  alias GoodDeal.Catalog.Product
  alias GoodDeal.Domain.{PromoCode, ShippingMethod}
  alias GoodDeal.Shop
  alias GoodDeal.ShoppingCart.{Address, Cart, CartItem, WishlistItem}

  def get_cart!(id), do: Repo.get!(Cart, id)

  @doc """
  Returns the shop's open cart, or a new open cart when its cart id is
  missing, unknown, or belongs to a cart that is no longer open.
  """
  def get_or_create_open_cart(%Shop{cart_id: nil, channel: channel}) do
    %Cart{shipping_method: channel.default_shipping_method}
    |> Cart.status_changeset(%{})
    |> Repo.insert!()
  end

  def get_or_create_open_cart(%Shop{cart_id: id} = shop) do
    case Repo.get(Cart, id) do
      %Cart{status: :open} = cart -> cart
      _ -> get_or_create_open_cart(%{shop | cart_id: nil})
    end
  end

  @doc """
  Whether the shop's cart exists and is no longer open. Every writer of cart contents
  below refuses such a cart with `{:error, :cart_closed}`; pages check first so they can
  reload. A missing or unknown cart is not closed: the writers fail on it as before.
  """
  def cart_closed?(%Shop{cart_id: id}), do: closed?(id)

  defp closed?(nil), do: false
  defp closed?(id), do: Repo.exists?(from c in Cart, where: c.id == ^id and c.status != :open)

  defp when_open(cart_id, write) do
    if closed?(cart_id), do: {:error, :cart_closed}, else: write.()
  end

  def set_cart_status(%Cart{} = cart, status) do
    cart
    |> Cart.status_changeset(%{status: status})
    |> Repo.update()
  end

  # The promo code and shipping method are written only here, after the channel's check.
  def apply_promo_code(%Shop{} = shop, code) do
    code = PromoCode.normalize(code)

    if PromoCode.valid?(shop.channel, code) do
      write_cart(shop, promo_code: code)
    else
      {:error, :invalid_promo_code}
    end
  end

  def select_shipping_method(%Shop{} = shop, method) do
    if ShippingMethod.find(shop.channel, method) do
      write_cart(shop, shipping_method: method)
    else
      {:error, :invalid_shipping_method}
    end
  end

  defp write_cart(shop, fields) do
    when_open(shop.cart_id, fn ->
      shop.cart_id |> get_cart!() |> Ecto.Changeset.change(fields) |> Repo.update()
    end)
  end

  def change_address(%Shop{} = shop, attrs) do
    address_changeset(get_cart!(shop.cart_id), attrs, shop.channel)
  end

  def save_address(%Shop{} = shop, attrs) do
    when_open(shop.cart_id, fn -> put_address(get_cart!(shop.cart_id), attrs, shop.channel) end)
  end

  defp put_address(cart, attrs, channel) do
    with {:ok, address} <-
           cart
           |> address_changeset(attrs, channel)
           |> Ecto.Changeset.apply_action(:insert) do
      cart
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_embed(:address, address)
      |> Repo.update()
    end
  end

  defp address_changeset(cart, attrs, channel) do
    Address.changeset(cart.address || %Address{}, attrs, channel.postal_code_length)
  end

  @doc """
  Items in the cart (not saved for later), oldest first, with products preloaded.
  """
  def list_cart_items(%Shop{cart_id: cart_id}), do: list_items(cart_id, false)

  def list_saved_items(%Shop{cart_id: cart_id}), do: list_items(cart_id, true)

  defp list_items(cart_id, saved?) do
    Repo.all(
      from i in CartItem,
        where: i.cart_id == ^cart_id and i.saved_for_later == ^saved?,
        order_by: [i.inserted_at, i.id],
        preload: :product
    )
  end

  def get_cart_item!(%Shop{cart_id: cart_id}, id) do
    CartItem
    |> Repo.get_by!(id: id, cart_id: cart_id)
    |> Repo.preload(:product)
  end

  def get_cart_item_for_product(%Shop{cart_id: cart_id}, product_id) do
    CartItem
    |> Repo.get_by(cart_id: cart_id, product_id: product_id)
    |> Repo.preload(:product)
  end

  @doc """
  Adds `quantity` of a product to the cart. A product already in the cart
  (or saved for later) gets its quantity increased and is moved back to the cart.
  """
  def add_item(%Shop{cart_id: cart_id}, product_id, quantity \\ 1) do
    when_open(cart_id, fn -> insert_item(cart_id, product_id, quantity) end)
  end

  defp insert_item(cart_id, product_id, quantity) do
    %CartItem{cart_id: cart_id, product_id: product_id}
    |> CartItem.changeset(%{quantity: quantity})
    |> Repo.insert(
      on_conflict: [inc: [quantity: quantity], set: [saved_for_later: false]],
      conflict_target: [:cart_id, :product_id],
      returning: true
    )
    |> case do
      {:ok, item} -> {:ok, Repo.preload(item, :product)}
      error -> error
    end
  end

  def update_item(%CartItem{} = item, attrs) do
    when_open(item.cart_id, fn -> item |> CartItem.changeset(attrs) |> Repo.update() end)
  end

  def change_quantity(%CartItem{} = item, delta) do
    update_item(item, %{quantity: max(item.quantity + delta, 1)})
  end

  def toggle_gift_wrap(%CartItem{} = item), do: update_item(item, %{gift_wrap: !item.gift_wrap})

  def save_for_later(%CartItem{} = item), do: update_item(item, %{saved_for_later: true})

  def move_to_cart(%CartItem{} = item), do: update_item(item, %{saved_for_later: false})

  @doc """
  Deletes a cart item. Deleting an item that is already gone is not an error.
  """
  def delete_item(%CartItem{id: id, cart_id: cart_id}) do
    when_open(cart_id, fn ->
      Repo.delete_all(from i in CartItem, where: i.id == ^id)
      :ok
    end)
  end

  @doc """
  Brings back an item whose removal was undone. Removal clears gift wrap.
  """
  def restore_item(%CartItem{} = item), do: update_item(item, %{gift_wrap: false})

  @doc """
  Checks that the cart has items and that each is in stock in the requested quantity.
  """
  def check_stock(%Shop{} = shop) do
    items = list_cart_items(shop)

    cond do
      items == [] -> {:error, :empty}
      Enum.any?(items, &(&1.quantity > &1.product.stock)) -> {:error, :out_of_stock}
      true -> {:ok, items}
    end
  end

  def list_wishlist(%Shop{cart_id: cart_id}) do
    Repo.all(
      from p in Product,
        join: w in WishlistItem,
        on: w.product_id == p.id,
        where: w.cart_id == ^cart_id,
        order_by: [w.inserted_at, w.id]
    )
  end

  def in_wishlist?(%Shop{cart_id: cart_id}, product_id) do
    Repo.exists?(
      from w in WishlistItem, where: w.cart_id == ^cart_id and w.product_id == ^product_id
    )
  end

  def toggle_wishlist(%Shop{cart_id: cart_id} = shop, product_id) do
    when_open(cart_id, fn ->
      if in_wishlist?(shop, product_id) do
        delete_wishlist_item(cart_id, product_id)
        :removed
      else
        Repo.insert!(%WishlistItem{cart_id: cart_id, product_id: product_id})
        :added
      end
    end)
  end

  def remove_from_wishlist(%Shop{cart_id: cart_id}, product_id) do
    when_open(cart_id, fn -> delete_wishlist_item(cart_id, product_id) end)
  end

  defp delete_wishlist_item(cart_id, product_id) do
    Repo.delete_all(
      from w in WishlistItem, where: w.cart_id == ^cart_id and w.product_id == ^product_id
    )

    :ok
  end

  def move_wishlist_item_to_cart(%Shop{cart_id: cart_id}, product_id) do
    when_open(cart_id, fn ->
      Repo.transaction(fn ->
        delete_wishlist_item(cart_id, product_id)
        {:ok, item} = insert_item(cart_id, product_id, 1)
        item
      end)
    end)
  end
end
