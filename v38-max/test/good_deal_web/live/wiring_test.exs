defmodule GoodDealWeb.WiringTest do
  use ExUnit.Case, async: true

  # each page's land/3 clauses are its wiring; read their heads from the source
  @pages [
    {GoodDealWeb.CartLive.Show, "lib/good_deal_web/live/cart_live/show.ex"},
    {GoodDealWeb.PortalLive.Show, "lib/good_deal_web/live/portal_live/show.ex"}
  ]

  defp landed(source) do
    {_, heads} =
      source
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:defp, _, [{:land, _, [_, key, {port, _}]} | _]} = node, acc ->
          {node, [{key, port} | acc]}

        node, acc ->
          {node, acc}
      end)

    heads
  end

  for {page, source} <- @pages do
    test "#{inspect(page)}: every declared output port has a land clause" do
      landed = landed(unquote(source))

      for {key, feature} <- unquote(page).features(), port <- Keyword.keys(feature.ports().out) do
        assert {key, port} in landed, "#{inspect(feature)} port #{port} has no land clause"
      end
    end

    test "#{inspect(page)}: every land clause names a declared port" do
      features = unquote(page).features()

      for {key, port} <- landed(unquote(source)) do
        assert port in Keyword.keys(features[key].ports().out), "no port #{inspect({key, port})}"
      end
    end
  end
end
