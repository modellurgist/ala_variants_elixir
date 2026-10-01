defmodule GoodDeal.Features.Checkout do
  @moduledoc """
  Taking payment for a cart: whether it can be paid for, and where paying has got to. Ports out:

    * `:status`        `:idle | :processing | :error | :complete`
    * `:blocked`       why paying can't start: `:empty` or `:out_of_stock`
    * `:ready_to_pay`  `{line_items, cart_id}`: the cart passed its checks
    * `:failed`        the reason a payment failed
    * `:done`          the paid cart's id

  Config: `stock_levels` (a function of product ids giving current levels) and `line_items` (a
  configured `Domain.Checkout`).
  """
  alias GoodDeal.Domain.{Checkout, Inventory}

  defstruct status: :idle, cart_id: nil, stock_levels: nil, line_items: nil

  def ports,
    do: %{
      in: [pay: :order, succeeded: :reference, failed: :reason],
      out: [
        status: :status,
        blocked: :reason,
        ready_to_pay: :payment,
        failed: :reason,
        done: :cart_id
      ]
    }

  def new(opts),
    do: %__MODULE__{
      stock_levels: Keyword.fetch!(opts, :stock_levels),
      line_items: Keyword.fetch!(opts, :line_items)
    }

  def pay(%__MODULE__{} = c, %{cart_id: cart_id, items: items}) do
    with {:ok, items} <- Checkout.validate(items),
         :ok <- Inventory.check_availability(items, c.stock_levels.(product_ids(items))) do
      c = %{c | status: :processing, cart_id: cart_id}

      {c,
       [status: :processing, ready_to_pay: {Checkout.line_items(c.line_items, items), cart_id}]}
    else
      {:error, :empty_cart} -> {c, [blocked: :empty]}
      {:error, _unavailable} -> {c, [blocked: :out_of_stock]}
    end
  end

  def succeeded(%__MODULE__{} = c, _reference),
    do: {%{c | status: :complete}, [status: :complete, done: c.cart_id]}

  def failed(%__MODULE__{} = c, reason),
    do: {%{c | status: :error}, [status: :error, failed: reason]}

  defp product_ids(items), do: Enum.map(items, & &1.product.id)
end
