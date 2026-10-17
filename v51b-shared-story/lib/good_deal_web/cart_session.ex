defmodule GoodDealWeb.CartSession do
  @moduledoc """
  The one source of the session's cart contracts: the keys the `SessionCart` plug
  writes and the LiveViews read, for the storefront cart and the portal's draft.
  Keeping the keys here (and the atom-write / string-read round-trip that Phoenix
  sessions impose) turns a silent cross-module agreement into an explicit one.
  """

  @key :cart_id
  @portal_key :portal_cart_id

  def cart_key, do: @key
  def portal_key, do: @portal_key

  def put(conn, cart_id), do: put(conn, @key, cart_id)
  def put(conn, key, cart_id), do: Plug.Conn.put_session(conn, key, cart_id)

  def current(conn), do: current(conn, @key)
  def current(conn, key), do: Plug.Conn.get_session(conn, key)

  @doc "Read a cart id from a LiveView `session` map (string-keyed at rest)."
  def fetch(session, key \\ @key) when is_map(session), do: Map.get(session, Atom.to_string(key))
end
