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

  def create_cart(attrs) do
    %Cart{}
    |> Cart.changeset(attrs)
    |> Repo.insert()
  end

  def get_cart!(id), do: Repo.get!(Cart, id)

  @doc """
  Returns the shop's open cart, or a new open cart when its cart id is
  missing, unknown, or belongs to a cart that is no longer open.
  """
  def get_or_create_open_cart(%Shop{cart_id: nil, channel: channel}) do
    {:ok, cart} = create_cart(%{shipping_method: channel.default_shipping_method})
    cart
  end

  def get_or_create_open_cart(%Shop{cart_id: id} = shop) do
    case Repo.get(Cart, id) do
      %Cart{status: :open} = cart -> cart
      _ -> get_or_create_open_cart(%{shop | cart_id: nil})
    end
  end

  def update_cart(%Cart{} = cart, attrs) do
    cart
    |> Cart.changeset(attrs)
    |> Repo.update()
  end

  def apply_promo_code(%Shop{} = shop, code) do
    code = PromoCode.normalize(code)

    if PromoCode.valid?(shop.channel, code) do
      update_cart(get_cart!(shop.cart_id), %{promo_code: code})
    else
      {:error, :invalid_promo_code}
    end
  end

  def select_shipping_method(%Shop{} = shop, method) do
    if ShippingMethod.find(shop.channel, method) do
      update_cart(get_cart!(shop.cart_id), %{shipping_method: method})
    else
      {:error, :invalid_shipping_method}
    end
  end

  def change_address(%Shop{} = shop, attrs) do
    address_changeset(get_cart!(shop.cart_id), attrs, shop.channel)
  end

  def save_address(%Shop{} = shop, attrs) do
    cart = get_cart!(shop.cart_id)

    with {:ok, address} <-
           cart
           |> address_changeset(attrs, shop.channel)
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
    item
    |> CartItem.changeset(attrs)
    |> Repo.update()
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
  def delete_item(%CartItem{id: id}) do
    Repo.delete_all(from i in CartItem, where: i.id == ^id)
    :ok
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
    if in_wishlist?(shop, product_id) do
      remove_from_wishlist(shop, product_id)
      :removed
    else
      Repo.insert!(%WishlistItem{cart_id: cart_id, product_id: product_id})
      :added
    end
  end

  def remove_from_wishlist(%Shop{cart_id: cart_id}, product_id) do
    Repo.delete_all(
      from w in WishlistItem, where: w.cart_id == ^cart_id and w.product_id == ^product_id
    )

    :ok
  end

  def move_wishlist_item_to_cart(%Shop{} = shop, product_id) do
    Repo.transaction(fn ->
      remove_from_wishlist(shop, product_id)
      {:ok, item} = add_item(shop, product_id)
      item
    end)
  end
end
