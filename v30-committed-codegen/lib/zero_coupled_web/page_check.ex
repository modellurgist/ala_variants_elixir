defmodule ZeroCoupledWeb.PageCheck do
  @moduledoc """
  Runtime helpers shared by every generated page: browser-param casting
  and a one-line manifest integrity check.

  In V29 these lived on the `ZeroCoupledWeb.Page` macro. V30 has no
  web-layer macro, so they live here — plain functions the generated
  code and the tests call directly.
  """

  @doc """
  Cast browser params per an intent's declared spec. Keys are the
  dasherized param names LiveView produces from `phx-value-*`.
  """
  def cast_params(params, spec) do
    Map.new(spec, fn {key, type} ->
      raw = Map.fetch!(params, dashed(key))
      {key, cast_value(raw, type)}
    end)
  end

  defp dashed(key), do: key |> Atom.to_string() |> String.replace("_", "-")

  defp cast_value(v, :int) when is_binary(v), do: String.to_integer(v)
  defp cast_value(v, :int) when is_integer(v), do: v
  defp cast_value(v, :string) when is_binary(v), do: v
  defp cast_value(v, :atom) when is_binary(v), do: String.to_existing_atom(v)
  defp cast_value(v, :atom) when is_atom(v), do: v

  @doc """
  Verify a page's manifest integrity (for a one-line test): every
  feature exports `init/1`; every fact is a struct; every reaction
  target and intent owner exports the referenced function; param specs
  use known types. Reads the page's generated `__manifest__/0`.
  """
  @spec verify(module()) :: :ok
  def verify(page) do
    manifest = page.__manifest__()

    for {slot, mod, _opts} <- manifest.features do
      Code.ensure_loaded!(mod)

      function_exported?(mod, :init, 1) ||
        raise "feature #{inspect(slot)} (#{inspect(mod)}) must export init/1"
    end

    for {fact_mod, targets} <- manifest.reactions do
      Code.ensure_loaded!(fact_mod)

      function_exported?(fact_mod, :__struct__, 1) ||
        raise "react #{inspect(fact_mod)}: facts must be structs (define it in the emitter's Facts module)"

      for {slot, mod, fun, _opts} <- targets do
        Code.ensure_loaded!(mod)

        function_exported?(mod, fun, 2) ||
          raise "reaction for #{inspect(fact_mod)} targets #{inspect(mod)}.#{fun}/2 (slot #{inspect(slot)}) which is not exported"

        Enum.any?(manifest.features, fn {s, _, _} -> s == slot end) ||
          raise "reaction for #{inspect(fact_mod)} targets undeclared slot #{inspect(slot)}"
      end
    end

    for {name, _slot, mod, params} <- manifest.intents do
      Code.ensure_loaded!(mod)

      function_exported?(mod, name, 2) ||
        raise "intent #{inspect(name)} declared but #{inspect(mod)}.#{name}/2 is not exported"

      for {key, type} <- params, type not in [:int, :string, :atom] do
        raise "intent #{inspect(name)} param #{inspect(key)} has unknown cast type #{inspect(type)}"
      end
    end

    :ok
  end
end
