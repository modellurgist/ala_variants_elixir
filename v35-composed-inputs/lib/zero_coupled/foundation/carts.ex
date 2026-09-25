defmodule ZeroCoupled.Foundation.Carts do
  @moduledoc """
  Foundation-layer persistence for carts and cart items.
  """

  import Ecto.Query, warn: false
  alias ZeroCoupled.Repo
  alias ZeroCoupled.Foundation.Schemas.{Cart, CartItem}

  @spec create() :: {:ok, Cart.t()} | {:error, Ecto.Changeset.t()}
  def create do
    Repo.insert(%Cart{status: :open})
  end

  @spec get(integer()) :: Cart.t() | nil
  def get(id) do
    Repo.get(Cart, id)
  end

  @doc """
  Return the id of an open cart for a session, reusing the given one while it is
  still open and minting a fresh cart otherwise (first visit, or the previous
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
    |> where([ci], ci.cart_id == ^cart_id)
    |> preload(:product)
    |> Repo.all()
  end

  @spec add_item(integer(), ZeroCoupled.Foundation.Schemas.Product.t()) ::
          {:ok, CartItem.t()} | {:error, Ecto.Changeset.t()}
  def add_item(cart_id, product) do
    Repo.insert(%CartItem{cart_id: cart_id, product: product, quantity: 1},
      conflict_target: [:cart_id, :product_id],
      on_conflict: [inc: [quantity: 1]]
    )
  end

  @spec update_quantity(integer(), integer(), integer()) :: {:ok, CartItem.t()} | {:error, Ecto.Changeset.t()}
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

  @spec complete(Cart.t()) :: {:ok, Cart.t()} | {:error, Ecto.Changeset.t()}
  def complete(%Cart{} = cart) do
    cart
    |> Cart.changeset(%{status: :completed})
    |> Repo.update()
  end
end
