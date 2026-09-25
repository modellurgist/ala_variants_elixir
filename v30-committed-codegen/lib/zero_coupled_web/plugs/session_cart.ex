defmodule ZeroCoupledWeb.Plugs.SessionCart do
  @moduledoc """
  Guarantees the connection carries a usable cart. On each request it asks the
  Carts context for an open cart id (reusing the session's when it is still open,
  minting one otherwise) and writes the result back to the session. The
  open-or-mint decision lives in `Carts.ensure_open/1`; this plug is only the
  wire between the session and that context.
  """
  @behaviour Plug

  import Plug.Conn

  alias ZeroCoupled.Foundation.Carts

  @impl true
  def init(default), do: default

  @impl true
  def call(conn, _config) do
    cart_id = Carts.ensure_open(get_session(conn, :cart_id))
    put_session(conn, :cart_id, cart_id)
  end
end
