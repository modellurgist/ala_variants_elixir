# The wishlist feature: one deletable file.

defmodule ZeroCoupled.Features.Wishlist do
  @moduledoc """
  A favourites list of *products* (not cart items) — distinct from
  SavedItems: hearting a product does not remove it from the cart, and
  moving a wishlisted product into the cart creates a new cart line
  (persisted at the shell edge).
  """

  @type product :: %{:id => term(), optional(atom()) => any()}
  @type t :: %__MODULE__{products: [product()]}

  defstruct products: []

  @spec init(keyword()) :: t()
  def init(_opts), do: %__MODULE__{}

  @spec list(t()) :: [product()]
  def list(%__MODULE__{products: products}), do: products

  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{products: products}), do: length(products)

  @spec member?(t(), term()) :: boolean()
  def member?(%__MODULE__{products: products}, product_id),
    do: Enum.any?(products, &(&1.id == product_id))

  @doc "Toggle a product's presence; returns whether it was `:added` or `:removed`."
  @spec toggle(t(), product()) :: {t(), :added | :removed}
  def toggle(%__MODULE__{} = wishlist, product) do
    if member?(wishlist, product.id) do
      {remove(wishlist, product.id), :removed}
    else
      {%{wishlist | products: wishlist.products ++ [product]}, :added}
    end
  end

  @spec remove(t(), term()) :: t()
  def remove(%__MODULE__{} = wishlist, product_id),
    do: %{wishlist | products: Enum.reject(wishlist.products, &(&1.id == product_id))}

  @doc "Remove and return a product by id."
  @spec take(t(), term()) :: {t(), product() | nil}
  def take(%__MODULE__{} = wishlist, product_id) do
    case Enum.find(wishlist.products, &(&1.id == product_id)) do
      nil -> {wishlist, nil}
      product -> {remove(wishlist, product_id), product}
    end
  end
end

defmodule ZeroCoupled.Features.Wishlist.Intents do
  @moduledoc false
  use ZeroCoupled.Feature.Intents, slot: :wishlist

  alias ZeroCoupled.Effects
  alias ZeroCoupled.Features.Wishlist

  # ── Intents ──────────────────────────────────────────────────────────

  intent :toggle_wishlist, params: [item_id: :int]

  def toggle_wishlist(session, %{item_id: item_id}) do
    # Cross-slot READ of the cart (allowed); writes only :wishlist.
    case Enum.find(session.cart.items, &(&1.id == item_id)) do
      nil ->
        {session, []}

      item ->
        {wishlist, result} = Wishlist.toggle(session.wishlist, item.product)
        msg = if result == :added, do: "Added to wishlist", else: "Removed from wishlist"

        stream =
          case result do
            :added -> Effects.stream_insert(:wishlist_products, item.product)
            :removed -> Effects.stream_delete(:wishlist_products, item.product)
          end

        {put_slot(session, wishlist), [stream, Effects.flash(:info, msg)]}
    end
  end

  intent :remove_wishlist, params: [product_id: :int]

  def remove_wishlist(session, %{product_id: product_id}) do
    case Wishlist.take(session.wishlist, product_id) do
      {wishlist, nil} ->
        {put_slot(session, wishlist), []}

      {wishlist, product} ->
        {put_slot(session, wishlist), [Effects.stream_delete(:wishlist_products, product)]}
    end
  end

  # ── Reactions ────────────────────────────────────────────────────────

  @doc "Reaction to `:added_from_wishlist`: the product is now a cart line — drop it here."
  def drop_product(%Wishlist{} = wishlist, %{product_id: product_id}) do
    case Wishlist.take(wishlist, product_id) do
      {wishlist, nil} -> {wishlist, []}
      {wishlist, product} -> {wishlist, [Effects.stream_delete(:wishlist_products, product)]}
    end
  end
end

defmodule ZeroCoupled.Features.Wishlist.Components do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true
  attr :product, :map, required: true

  def wishlist_row(assigns) do
    ~H"""
    <div id={@id} class="grid grid-cols-[4rem_1fr_auto_auto] items-center gap-4 border-b py-4">
      <img class="w-16 h-16 object-contain" src={@product.thumbnail} alt={@product.name} />
      <div>
        <div class="font-medium"><%= @product.name %></div>
        <div class="text-sm text-zinc-500"><%= Money.new(@product.amount) %></div>
      </div>
      <button
        phx-click="add_wishlisted_to_cart"
        phx-value-product-id={@product.id}
        class="text-sm font-medium text-blue-600"
      >
        Add to cart
      </button>
      <button phx-click="remove_wishlist" phx-value-product-id={@product.id} class="text-sm text-red-500">
        Remove
      </button>
    </div>
    """
  end
end
