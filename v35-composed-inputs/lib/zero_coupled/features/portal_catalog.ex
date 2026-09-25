# The portal's product-browse feature: one deletable file.

defmodule ZeroCoupled.Features.PortalCatalog do
  @moduledoc """
  Slot module for the `:catalog` slot — the browsable product list with
  live stock. Read-only toward products; ordering happens through the
  `:order` slot.
  """

  alias ZeroCoupled.Domain.StockStatus

  @type t :: %__MODULE__{products: [map()]}

  defstruct products: []

  @spec init(keyword()) :: t()
  def init(opts), do: %__MODULE__{products: opts[:products] || []}

  @spec list(t()) :: [map()]
  def list(%__MODULE__{products: products}), do: products

  @doc "Row port: the projected value the portal-products stream carries."
  @spec row(map()) :: map()
  def row(product) do
    %{
      id: product.id,
      product: %{thumbnail: product.thumbnail, name: product.name, amount: product.amount},
      stock_status: StockStatus.call(product.stock)
    }
  end
end

defmodule ZeroCoupled.Features.PortalCatalog.Intents do
  @moduledoc false
  use ZeroCoupled.Feature.Intents, slot: :catalog

  alias ZeroCoupled.Effects
  alias ZeroCoupled.Features.PortalCatalog
  alias ZeroCoupled.Web.Contracts

  # ── Reactions ────────────────────────────────────────────────────────

  @doc "Reaction to `Broadcast.Facts.StockChanged`: refresh the product row."
  def set_stock(%PortalCatalog{} = catalog, %{product_id: product_id, stock: stock}) do
    case Enum.find(catalog.products, &(&1.id == product_id)) do
      nil ->
        {catalog, []}

      product ->
        product = %{product | stock: stock}

        catalog = %{
          catalog
          | products: Enum.map(catalog.products, &if(&1.id == product_id, do: product, else: &1))
        }

        {catalog,
         [Effects.stream_insert(Contracts.stream_name(:catalog), PortalCatalog.row(product))]}
    end
  end
end

defmodule ZeroCoupled.Features.PortalCatalog.Components do
  @moduledoc "Markup owned by the portal-catalog feature — thin over the catalog."
  use Phoenix.Component

  import ZeroCoupled.Catalog.ProductLineRow
  import ZeroCoupled.Catalog.StockBadge
  alias ZeroCoupled.Web.Contracts

  attr :id, :string, required: true
  attr :row, :map, required: true, doc: "projected: %{id, product, stock_status}"

  def catalog_row(assigns) do
    ~H"""
    <.product_line id={@id} product={@row.product} cols="4rem_1fr_auto">
      <:detail>
        <.stock_badge status={@row.stock_status} />
      </:detail>
      <:actions>
        <form phx-submit={Contracts.event(:add_to_order)} class="flex items-center gap-2">
          <input type="hidden" name="product-id" value={@row.id} />
          <input
            type="number"
            name="quantity"
            value="10"
            min="1"
            class="w-20 rounded border border-zinc-300 px-2 py-1 text-sm text-right"
          />
          <button
            type="submit"
            disabled={@row.stock_status == :out_of_stock}
            class="rounded bg-zinc-900 text-white px-3 py-1.5 text-sm font-medium disabled:opacity-40"
          >
            Add
          </button>
        </form>
      </:actions>
    </.product_line>
    """
  end
end
