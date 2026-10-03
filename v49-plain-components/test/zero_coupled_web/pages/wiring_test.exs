defmodule ZeroCoupledWeb.WiringTest do
  @moduledoc """
  Each page's wiring is its `handle_info` clauses, one per port an instance sends. This reads the
  clause heads from the page's source and checks that every port each instance sends (derived from
  its feature's declared ports), and the undo clock's message, has a clause, and that no clause
  names a port nothing sends.
  """
  use ExUnit.Case, async: true

  alias ZeroCoupled.State.{
    Cart,
    Checkout,
    OrderLines,
    PortalCatalog,
    PortalSubmit,
    SavedItems,
    Undo,
    Wishlist
  }

  # {name, port} for every `def handle_info({:name, :port, _}, _)` head in the page's source
  defp clause_heads(page) do
    {_, heads} =
      page.__info__(:compile)[:source]
      |> to_string()
      |> File.read!()
      |> Code.string_to_quoted!()
      |> Macro.prewalk([], fn
        {:def, _, [{:handle_info, _, [{:{}, _, [name, port, _]}, _]} | _]} = node, acc
        when is_atom(name) and is_atom(port) ->
          {node, [{name, port} | acc]}

        {:def, _, [{:when, _, [{:handle_info, _, [{:{}, _, [name, port, _]}, _]} | _]} | _]} =
            node,
        acc
        when is_atom(name) and is_atom(port) ->
          {node, [{name, port} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.uniq(heads)
  end

  defp check(page, instances) do
    sent =
      for({name, panel} <- instances, port <- panel.sent_port_outputs(), do: {name, port}) ++
        if(Keyword.has_key?(instances, :undo), do: [{:undo, :expire}], else: [])

    heads = clause_heads(page)
    assert sent -- heads == [], "#{inspect(page)} has no clause for #{inspect(sent -- heads)}"

    assert heads -- sent == [],
           "#{inspect(page)} handles ports nothing sends: #{inspect(heads -- sent)}"
  end

  test "the cart page has a clause for everything its instances send" do
    check(ZeroCoupledWeb.CartPage,
      cart: Cart.Panel,
      undo: Undo.Banner,
      saved: SavedItems.Panel,
      wishlist: Wishlist.Panel,
      checkout: Checkout.Panel
    )
  end

  test "the portal page has a clause for everything its instances send" do
    check(ZeroCoupledWeb.PortalPage,
      catalog: PortalCatalog.Panel,
      order: OrderLines.Panel,
      undo: Undo.Banner,
      submit: PortalSubmit.Panel
    )
  end

  test "the product pages have a clause for what their record form sends" do
    check(ZeroCoupledWeb.ProductLive.Index, product_form: ZeroCoupled.Catalog.RecordForm)
    check(ZeroCoupledWeb.ProductLive.Show, product_form: ZeroCoupled.Catalog.RecordForm)
  end
end

defmodule ZeroCoupledWeb.DrawingTest do
  use ExUnit.Case, async: true

  test "the cart page's diagram is drawn from its handle_info and handle_async clauses" do
    chart = ZeroCoupledWeb.Paradigms.Drawing.mermaid(ZeroCoupledWeb.CartPage)
    assert chart =~ ~s(cart -->|"removed → capture"| undo)
    assert chart =~ ~s(wishlist -.->|"taken"| add_line["task AddLine.run"])
    assert chart =~ ~s(add_line -->|"ok → receive"| cart)
  end
end
