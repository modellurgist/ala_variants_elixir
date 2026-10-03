defmodule ZeroCoupled.Domain.BuildLineItems do
  @moduledoc "Turns cart items into payment line items, in the currency the store configures once."
  defstruct currency: nil

  def new(opts), do: %__MODULE__{currency: Keyword.fetch!(opts, :currency)}

  @spec call(%__MODULE__{}, [%{product: map(), quantity: integer()}]) :: [map()]
  def call(%__MODULE__{currency: currency}, items) do
    for item <- items do
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
