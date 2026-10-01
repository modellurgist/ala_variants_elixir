defmodule ZeroCoupledWeb.WiringTest do
  use ExUnit.Case, async: true

  # a port with no binding is dropped silently, so each page must bind or ground every one
  for page <- [ZeroCoupledWeb.CartPage, ZeroCoupledWeb.PortalPage] do
    test "#{inspect(page)} binds or grounds every feature output" do
      page = unquote(page)
      bound = Map.keys(page.bindings(1)) ++ page.grounded()

      for {key, feature} <- page.features(), port <- Keyword.keys(feature.ports().out) do
        assert {key, port} in bound,
               "#{inspect(feature)} port #{port} is neither bound nor grounded"
      end
    end

    test "#{inspect(page)} binds only ports its features declare" do
      page = unquote(page)
      features = page.features()

      for {key, port} <- Map.keys(page.bindings(1)), key != :page do
        assert port in Keyword.keys(features[key].ports().out), "no port #{inspect({key, port})}"
      end
    end
  end
end
