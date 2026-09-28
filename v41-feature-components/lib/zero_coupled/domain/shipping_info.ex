defmodule ZeroCoupled.Domain.ShippingInfo do
  @moduledoc """
  Single-function domain abstraction: shipping-method metadata for display,
  read from a **passed-in rate table** (V34). Generic over the map the
  composition supplies; no method names or labels baked in.
  """

  @type rates :: %{atom() => map()}

  @spec method_names(rates()) :: [atom()]
  def method_names(rates), do: Map.keys(rates)

  @spec label(atom(), rates()) :: String.t()
  def label(method, rates), do: rates[method].label
end
