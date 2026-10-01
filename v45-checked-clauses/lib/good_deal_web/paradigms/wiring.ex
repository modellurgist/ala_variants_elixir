defmodule GoodDealWeb.Paradigms.Wiring do
  @moduledoc """
  Checks that a page's `land/3` clauses wire every port its features declare, and nothing else.
  A page lists its features with `features/0` (`%{key => FeatureModule}`); each feature declares
  `ports/0`. `gaps/1` reads the page's own source (from its compile info), so a page's coverage test
  is one line:

      assert Wiring.gaps(CartLive.Show) == %{unwired: [], unknown: []}

  Optionally, `use GoodDealWeb.Paradigms.Wiring` makes the same check at compile time, reading the
  page's `@features` attribute (which its `features/0` returns): the build fails on a gap.
  """

  @doc "`%{unwired: [{key, port}], unknown: [{key, port}]}` for a page module."
  def gaps(page) do
    page.__info__(:compile)[:source]
    |> to_string()
    |> File.read!()
    |> Code.string_to_quoted!()
    |> heads()
    |> compare(page.features())
  end

  @doc "The `{key, port}` of every `land/3` clause head in quoted source."
  def heads(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {kind, _, [{:land, _, [_, key, {port, _}]} | _]} = node, acc when kind in [:def, :defp] ->
          {node, [{key, port} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  def compare(landed, features) do
    declared =
      for {key, feature} <- features, port <- Keyword.keys(feature.ports().out), do: {key, port}

    %{unwired: declared -- landed, unknown: Enum.uniq(landed) -- declared}
  end

  defmacro __using__(_opts) do
    quote do
      @on_definition GoodDealWeb.Paradigms.Wiring
      @before_compile GoodDealWeb.Paradigms.Wiring
      Module.register_attribute(__MODULE__, :wiring_landed, accumulate: true)
    end
  end

  def __on_definition__(env, kind, :land, [_, key, {port, _}], _guards, _body)
      when kind in [:def, :defp],
      do: Module.put_attribute(env.module, :wiring_landed, {key, port})

  def __on_definition__(_env, _kind, _name, _args, _guards, _body), do: :ok

  defmacro __before_compile__(env) do
    landed = Module.get_attribute(env.module, :wiring_landed)
    features = Module.get_attribute(env.module, :features) || %{}
    Enum.each(features, fn {_, feature} -> Code.ensure_compiled!(feature) end)

    case compare(landed, features) do
      %{unwired: [], unknown: []} ->
        :ok

      gaps ->
        raise CompileError,
          file: env.file,
          line: 0,
          description: "land/3 wiring gaps in #{inspect(env.module)}: #{inspect(gaps)}"
    end

    nil
  end
end
