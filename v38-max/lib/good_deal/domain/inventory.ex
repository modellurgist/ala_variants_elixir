defmodule GoodDeal.Domain.Inventory do
  @moduledoc """
  Stock rules. A configured instance (`new(low_at: n)`) classifies a level; `check_availability/2`
  compares requested quantities with levels. No persistence, no framework.
  """
  defstruct low_at: 0

  @type stock_status :: :in_stock | :low_stock | :out_of_stock

  def new(opts), do: %__MODULE__{low_at: Keyword.fetch!(opts, :low_at)}

  @spec status(%__MODULE__{}, integer()) :: stock_status()
  def status(%__MODULE__{}, stock) when stock <= 0, do: :out_of_stock
  def status(%__MODULE__{low_at: low}, stock) when stock <= low, do: :low_stock
  def status(%__MODULE__{}, _stock), do: :in_stock

  @spec check_availability([%{product: %{id: integer()}, quantity: integer()}], %{
          integer() => integer()
        }) ::
          :ok | {:error, [%{product_id: integer(), requested: integer(), available: integer()}]}
  def check_availability(items, stock_levels) do
    unavailable =
      for item <- items,
          available = Map.get(stock_levels, item.product.id, 0),
          item.quantity > available do
        %{product_id: item.product.id, requested: item.quantity, available: available}
      end

    if unavailable == [], do: :ok, else: {:error, unavailable}
  end
end
