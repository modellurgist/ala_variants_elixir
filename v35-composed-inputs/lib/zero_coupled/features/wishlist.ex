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

  @doc "L5 presentation port (`render: :render_data` → `@wishlist`)."
  @spec render_data(t()) :: map()
  def render_data(%__MODULE__{} = wishlist) do
    %{count: count(wishlist), product_ids: Enum.map(wishlist.products, & &1.id)}
  end

  @doc "Row port: the projected value the wishlist stream carries."
  @spec row(product()) :: map()
  def row(product) do
    %{
      id: product.id,
      product: %{thumbnail: product.thumbnail, name: product.name, amount: product.amount}
    }
  end
end

defmodule ZeroCoupled.Features.Wishlist.Intents do
  @moduledoc false
  use ZeroCoupled.Feature.Intents, slot: :wishlist

  alias ZeroCoupled.Effects
  alias ZeroCoupled.Features.Wishlist
  alias ZeroCoupled.Web.Contracts

  # ── Intents ──────────────────────────────────────────────────────────

  # R2 (V35): the cart item is resolved by the *composition* (the page shell
  # finds it and passes it in), so this feature never reads the `:cart` peer
  # slot. It writes only `:wishlist`. `nil` = the shell found no such item.
  def toggle_wishlist(session, nil), do: {session, []}

  def toggle_wishlist(session, item) do
    {wishlist, result} = Wishlist.toggle(session.wishlist, item.product)
    msg = if result == :added, do: "Added to wishlist", else: "Removed from wishlist"
    row = Wishlist.row(item.product)

    stream =
      case result do
        :added -> Effects.stream_insert(Contracts.stream_name(:wishlist), row)
        :removed -> Effects.stream_delete(Contracts.stream_name(:wishlist), row)
      end

    {put_slot(session, wishlist), [stream, Effects.flash(:info, msg)]}
  end

  intent :remove_wishlist, params: [product_id: :int]

  def remove_wishlist(session, %{product_id: product_id}) do
    case Wishlist.take(session.wishlist, product_id) do
      {wishlist, nil} ->
        {put_slot(session, wishlist), []}

      {wishlist, product} ->
        {put_slot(session, wishlist),
         [Effects.stream_delete(Contracts.stream_name(:wishlist), Wishlist.row(product))]}
    end
  end

  # ── Reactions ────────────────────────────────────────────────────────

  @doc "Reaction to `:added_from_wishlist`: the product is now a cart line — drop it here."
  def drop_product(%Wishlist{} = wishlist, %{product_id: product_id}) do
    case Wishlist.take(wishlist, product_id) do
      {wishlist, nil} ->
        {wishlist, []}

      {wishlist, product} ->
        {wishlist,
         [Effects.stream_delete(Contracts.stream_name(:wishlist), Wishlist.row(product))]}
    end
  end
end

defmodule ZeroCoupled.Features.Wishlist.Components do
  @moduledoc false
  use Phoenix.Component

  import ZeroCoupled.Catalog.ProductLineRow
  import ZeroCoupled.Catalog.ActionButton
  alias ZeroCoupled.Web.Contracts

  attr :id, :string, required: true
  attr :row, :map, required: true, doc: "projected: %{id, product}"

  def wishlist_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto_auto">
      <:actions>
        <.action_button
          on={Contracts.event(:add_wishlisted_to_cart)}
          phx-value-product-id={@row.id}
          label="Add to cart"
        />
        <.action_button
          on={Contracts.event(:remove_wishlist)}
          phx-value-product-id={@row.id}
          label="Remove"
          class="text-sm font-medium text-red-500"
        />
      </:actions>
    </.product_line>
    """
  end
end
