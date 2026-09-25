defmodule ZeroCoupledWeb.Plugs.SessionCart do
  @moduledoc """
  Guarantees the connection carries a usable cart under a session key. The key
  defaults to `:cart_id` but is overridable (`key: :portal_cart_id`), so the
  portal's order draft stays separate from the storefront cart in the same
  browser session. The open-or-mint decision lives in `Carts.ensure_open/1`;
  this plug only wires the session key to it.
  """
  @behaviour Plug

  import Plug.Conn

  alias ZeroCoupled.Foundation.Carts

  @impl true
  def init(opts), do: Keyword.get(opts, :key, :cart_id)

  @impl true
  def call(conn, key) do
    cart_id = Carts.ensure_open(get_session(conn, key))
    put_session(conn, key, cart_id)
  end
end
