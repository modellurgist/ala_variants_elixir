defmodule GoodDeal.Domain.Checkout do
  @moduledoc """
  Turns cart lines into gateway-neutral line items, in the currency the store configures once.
  Knows nothing about the payment provider, Ecto, or LiveView.
  """
  defstruct currency: nil

  @type line_item :: %{
          name: String.t(),
          description: String.t(),
          image_url: String.t(),
          unit_amount: integer(),
          currency: String.t(),
          quantity: integer()
        }

  def new(opts), do: %__MODULE__{currency: Keyword.fetch!(opts, :currency)}

  @spec validate([term()]) :: {:ok, [term()]} | {:error, :empty_cart}
  def validate([]), do: {:error, :empty_cart}
  def validate(items) when is_list(items), do: {:ok, items}

  @spec line_items(%__MODULE__{}, [%{product: map(), quantity: integer()}]) :: [line_item()]
  def line_items(%__MODULE__{currency: currency}, cart_items) do
    for item <- cart_items do
      %{
        name: item.product.name,
        description: item.product.description,
        image_url: item.product.thumbnail,
        unit_amount: item.product.amount,
        currency: currency,
        quantity: item.quantity
      }
    end
  end
end
