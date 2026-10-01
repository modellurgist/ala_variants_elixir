defmodule GoodDealWeb.WiringTest do
  use ExUnit.Case, async: true

  # the page's land/3 clauses are its wiring; read their heads from the source
  @source "lib/good_deal_web/live/cart_live/show.ex"
  @features %{cart: GoodDeal.Features.Cart, checkout: GoodDeal.Features.Checkout}

  defp landed do
    {_, heads} =
      @source
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:defp, _, [{:land, _, [_, key, {port, _}]} | _]} = node, acc ->
          {node, [{key, port} | acc]}

        {:defp, _, [{:when, _, [{:land, _, [_, key, {port, _}]} | _]} | _]} = node, acc ->
          {node, [{key, port} | acc]}

        node, acc ->
          {node, acc}
      end)

    heads
  end

  test "every declared output port has a land clause" do
    landed = landed()

    for {key, feature} <- @features, port <- Keyword.keys(feature.ports().out) do
      assert {key, port} in landed, "#{inspect(feature)} port #{port} has no land clause"
    end
  end

  test "every land clause names a declared port" do
    for {key, port} <- landed() do
      assert port in Keyword.keys(@features[key].ports().out), "no port #{inspect({key, port})}"
    end
  end
end
