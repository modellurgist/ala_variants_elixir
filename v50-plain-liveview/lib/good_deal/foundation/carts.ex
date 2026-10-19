# ala:accept vocabulary -- the five ways a stored line changes; merging held and saved would only hide one
defmodule GoodDeal.Foundation.Carts do
  @moduledoc """
  Foundation-layer persistence for carts and cart items.
  """

  import Ecto.Query, warn: false
  alias GoodDeal.Repo
  alias GoodDeal.Foundation.Schemas.{Cart, CartItem}

  @spec create() :: {:ok, Cart.t()} | {:error, Ecto.Changeset.t()}
  def create do
    Repo.insert(%Cart{status: :open})
  end

  @spec get(integer()) :: Cart.t() | nil
  def get(id) do
    Repo.get(Cart, id)
  end

  @doc """
  Return the id of an open cart for this session, reusing the given one when it
  is still open and minting a fresh cart otherwise (first visit, or the previous
  cart was checked out). Keeping the open-or-mint decision here lets the session
  plug stay pure wiring.
  """
  @spec ensure_open(integer() | nil) :: integer()
  def ensure_open(cart_id) do
    case cart_id && get(cart_id) do
      %Cart{status: :open, id: id} ->
        id

      _ ->
        {:ok, %Cart{id: id}} = create()
        id
    end
  end

  @spec list_items(integer()) :: [CartItem.t()]
  def list_items(cart_id) do
    CartItem
    |> where([ci], ci.cart_id == ^cart_id and is_nil(ci.removed_at) and is_nil(ci.saved_at))
    |> preload(:product)
    |> Repo.all()
  end

  @spec list_saved(integer()) :: [CartItem.t()]
  def list_saved(cart_id) do
    CartItem
    |> where([ci], ci.cart_id == ^cart_id and is_nil(ci.removed_at) and not is_nil(ci.saved_at))
    |> order_by([ci], asc: ci.saved_at)
    |> preload(:product)
    |> Repo.all()
  end

  @spec add_item(integer(), GoodDeal.Foundation.Schemas.Product.t()) ::
          {:ok, CartItem.t()} | {:error, Ecto.Changeset.t()}
  def add_item(cart_id, product) do
    # a held line for this product would swallow the new one and leave with it
    CartItem
    |> where([ci], ci.cart_id == ^cart_id and ci.product_id == ^product.id)
    |> where([ci], not is_nil(ci.removed_at))
    |> Repo.delete_all()

    # one row per product, so a saved line comes back into the cart with the added one
    Repo.insert(%CartItem{cart_id: cart_id, product: product, quantity: 1},
      conflict_target: [:cart_id, :product_id],
      on_conflict: [inc: [quantity: 1], set: [saved_at: nil]]
    )
  end

  @spec update_quantity(integer(), integer(), integer()) ::
          {:ok, CartItem.t()} | {:error, Ecto.Changeset.t()}
  def update_quantity(cart_id, item_id, quantity) do
    CartItem
    |> where([ci], ci.cart_id == ^cart_id and ci.id == ^item_id)
    |> Repo.one!()
    |> CartItem.changeset(%{quantity: quantity})
    |> Repo.update()
  end

  @spec remove_item(integer(), integer()) :: {non_neg_integer(), nil}
  def remove_item(cart_id, item_id) do
    CartItem
    |> where([ci], ci.cart_id == ^cart_id and ci.id == ^item_id)
    |> Repo.delete_all()
  end

  @doc """
  Make held removals final: those held for at least `window_ms`, or all of them. A hold whose page
  is gone has no clock left, so this is what ends it.
  """
  @spec finalize_holds(integer(), non_neg_integer()) :: {non_neg_integer(), nil}
  def finalize_holds(cart_id, window_ms \\ 0) do
    cutoff = DateTime.add(DateTime.utc_now(), -window_ms, :millisecond)

    CartItem
    |> where([ci], ci.cart_id == ^cart_id and ci.removed_at <= ^cutoff)
    |> Repo.delete_all()
  end

  defp mark(cart_id, item_id, marks) do
    CartItem
    |> where([ci], ci.cart_id == ^cart_id and ci.id == ^item_id)
    |> Repo.update_all(set: marks)
  end

  @spec complete(Cart.t()) :: {:ok, Cart.t()} | {:error, Ecto.Changeset.t()}
  def complete(%Cart{} = cart) do
    cart
    |> Cart.changeset(%{status: :completed})
    |> Repo.update()
  end

  @doc """
  Apply a change to a stored line: `{:quantity, cart_id, item_id, qty}`, `{:held, cart_id, item_id}`
  (removed but undoable, left out of every read), `{:saved, cart_id, item_id}` (set aside: read
  only by `list_saved/1`), `{:kept, cart_id, item_id}` (back in the cart) or
  `{:removed, cart_id, item_id}`.
  """
  def apply_change({:quantity, cart_id, item_id, quantity}),
    do: update_quantity(cart_id, item_id, quantity)

  def apply_change({:held, cart_id, item_id}),
    do: mark(cart_id, item_id, removed_at: DateTime.utc_now())

  def apply_change({:saved, cart_id, item_id}),
    do: mark(cart_id, item_id, saved_at: DateTime.utc_now())

  def apply_change({:kept, cart_id, item_id}),
    do: mark(cart_id, item_id, removed_at: nil, saved_at: nil)

  def apply_change({:removed, cart_id, item_id}), do: remove_item(cart_id, item_id)
end
