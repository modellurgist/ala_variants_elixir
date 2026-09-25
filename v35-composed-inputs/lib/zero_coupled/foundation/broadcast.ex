defmodule ZeroCoupled.Foundation.Broadcast do
  @moduledoc """
  Foundation-layer PubSub transport, carrying **typed facts** (V32
  Enhancement B).

  V30 broadcast bare tagged tuples (`{:stock_changed, id, stock}`); every
  consumer restated the tuple as a literal `handle_info` pattern and fell
  through to the catch-all on drift — a *silent* failure. Here the message
  is a struct with `@enforce_keys`, so a wrong/missing field is a compile
  error at the emit site, and a consumer matches a compile-checked shape.

  A manifest page needs no per-message `handle_info` clause: one generic
  clause forwards any *declared* fact struct into the page's generated
  `apply_fact/2`, so the wire

      {Broadcast.Facts.StockChanged, to: {:cart, CartItems.Intents, :set_stock}}

  is the whole integration — the generator was already fact-module-agnostic.
  """

  defmodule Facts do
    @moduledoc "Cross-process facts owned by the storefront foundation."

    defmodule StockChanged do
      @moduledoc false
      @enforce_keys [:product_id, :stock]
      defstruct [:product_id, :stock]
    end

    defmodule ProductSaved do
      @moduledoc false
      @enforce_keys [:product]
      defstruct [:product]
    end
  end

  @topic "storefront"

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(ZeroCoupled.PubSub, @topic)

  @spec stock_changed(integer(), integer()) :: :ok | {:error, term()}
  def stock_changed(product_id, stock),
    do: broadcast(%Facts.StockChanged{product_id: product_id, stock: stock})

  @spec product_saved(struct()) :: :ok | {:error, term()}
  def product_saved(product), do: broadcast(%Facts.ProductSaved{product: product})

  defp broadcast(%_{} = fact), do: Phoenix.PubSub.broadcast(ZeroCoupled.PubSub, @topic, fact)
end
