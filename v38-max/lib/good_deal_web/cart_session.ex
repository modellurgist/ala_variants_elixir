defmodule GoodDealWeb.CartSession do
  @moduledoc """
  The one source of the cart-id session contract: the key the `SessionCart`
  plug writes and the cart LiveViews read. Keeping the key here (and the
  atom-write / string-read round-trip that Phoenix sessions impose) in one
  named place turns a silent cross-module agreement into an explicit one.
  """

  @key :cart_id

  def put(conn, cart_id), do: Plug.Conn.put_session(conn, @key, cart_id)

  def current(conn), do: Plug.Conn.get_session(conn, @key)

  @doc "Read the cart id from a LiveView `session` map (string-keyed at rest)."
  def fetch(session) when is_map(session), do: Map.get(session, Atom.to_string(@key))
end
