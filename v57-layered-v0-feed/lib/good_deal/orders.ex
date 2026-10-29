defmodule GoodDeal.Orders do
  @moduledoc """
  The Orders context.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias GoodDeal.Repo

  alias GoodDeal.Catalog.Product
  alias GoodDeal.Orders.{Order, PurchaseOrder}
  alias GoodDeal.{ChangeFeed, Shop}
  alias GoodDeal.ShoppingCart.Cart

  def get_order!(id), do: Order |> Repo.get!(id) |> Repo.preload(:line_items)

  def change_purchase_order(%Shop{channel: channel}, attrs \\ %{}) do
    PurchaseOrder.changeset(%PurchaseOrder{}, attrs, channel.po_number)
  end

  @doc """
  Turns the shop's paid storefront cart into an order: creates the order, completes the
  cart and decrements stock, then publishes each new stock level. `summary` is the
  caller's price summary, with the items it priced, which must be the cart's.
  """
  def complete_checkout(%Shop{} = shop, summary) do
    cart = Repo.get!(Cart, shop.cart_id)
    attrs = %{source: :storefront, address: address_map(cart.address)}

    Multi.new()
    |> place_order(cart, summary, attrs)
    |> decrement_stock(summary.items)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order} = changes} ->
        for {{:product, _id}, product} <- changes,
            do: ChangeFeed.publish(:stock, product.id, %{stock: product.stock})

        {:ok, order}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Submits the shop's portal draft as an order under a purchase-order number.
  """
  def submit_portal_order(%Shop{} = shop, summary, po_params) do
    with {:ok, po} <-
           shop
           |> change_purchase_order(po_params)
           |> Ecto.Changeset.apply_action(:insert) do
      Multi.new()
      |> place_order(Repo.get!(Cart, shop.cart_id), summary, %{
        source: :portal,
        po_number: po.number
      })
      |> Repo.transaction()
      |> case do
        {:ok, %{order: order}} -> {:ok, order}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  defp place_order(multi, cart, summary, attrs) do
    line_items =
      Enum.map(summary.items, fn item ->
        %{
          product_id: item.product_id,
          name: item.product.name,
          unit_price: item.product.amount,
          quantity: item.quantity
        }
      end)

    attrs =
      summary
      |> Map.take([:subtotal, :discount, :gift_wrap, :shipping, :total])
      |> Map.merge(attrs)
      |> Map.put(:line_items, line_items)

    multi
    |> Multi.run(:items_in_cart, fn _repo, _changes -> items_in_cart(cart, summary.items) end)
    |> Multi.insert(:order, Order.changeset(%Order{cart_id: cart.id}, attrs))
    |> Multi.update(:cart, Cart.status_changeset(cart, %{status: :completed}))
  end

  defp items_in_cart(cart, items) do
    if Enum.all?(items, &(&1.cart_id == cart.id)), do: {:ok, true}, else: {:error, :not_in_cart}
  end

  defp decrement_stock(multi, items) do
    Enum.reduce(items, multi, fn item, multi ->
      Multi.run(multi, {:product, item.product_id}, fn repo, _changes ->
        decrement_product_stock(repo, item)
      end)
    end)
  end

  defp decrement_product_stock(repo, item) do
    query =
      from p in Product,
        where: p.id == ^item.product_id and p.stock >= ^item.quantity,
        select: p

    case repo.update_all(query, inc: [stock: -item.quantity]) do
      {1, [product]} -> {:ok, product}
      {0, _} -> {:error, :out_of_stock}
    end
  end

  defp address_map(nil), do: nil
  defp address_map(address), do: Map.from_struct(address)
end
