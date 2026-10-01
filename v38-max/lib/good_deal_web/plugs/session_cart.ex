defmodule GoodDealWeb.Plugs.SessionCart do
  @moduledoc """
  Guarantees the connection carries a usable cart. On every request it asks the
  Carts context for an open cart id (reusing the session's when it is still open,
  minting one otherwise) and writes the result back to the session. The
  open-or-mint decision lives in `Carts.ensure_open/1`; this plug is just the
  wire between the session and that context.
  """
  @behaviour Plug

  alias GoodDeal.Foundation.Carts
  alias GoodDealWeb.CartSession

  @impl true
  def init(default), do: default

  @impl true
  def call(conn, _config) do
    cart_id = Carts.ensure_open(CartSession.current(conn))
    CartSession.put(conn, cart_id)
  end
end
