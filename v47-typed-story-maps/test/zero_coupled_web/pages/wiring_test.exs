defmodule ZeroCoupledWeb.WiringTest do
  use ExUnit.Case, async: true
  alias ZeroCoupledWeb.Paradigms.{Binder, Diagram}

  # every port typed and bound or grounded, every binding between ports of one type, no closures
  for page <- [ZeroCoupledWeb.CartPage, ZeroCoupledWeb.PortalPage] do
    test "#{inspect(page)}'s composition is sound" do
      assert Diagram.problems(unquote(page).composition(1)) == []
    end
  end

  test "the product pages' record forms are wired soundly" do
    assert Diagram.problems(ZeroCoupledWeb.ProductLive.Index.composition()) == []
    assert Diagram.problems(ZeroCoupledWeb.ProductLive.Show.composition(1)) == []
  end

  test "no two stories on a page claim the same event" do
    for page <- [ZeroCoupledWeb.CartPage, ZeroCoupledWeb.PortalPage] do
      {_page, stories} = page.composition(1)
      events = Enum.flat_map(stories, fn {_, s} -> s.module.events() end)
      assert events -- Enum.uniq(events) == [], inspect(page)
    end
  end

  defmodule Lines do
    def ports, do: %{in: [add: :item, load: :items], out: [summary: :summary, rows: :row_change]}
    def add(l, _), do: {l, []}
    def load(l, _), do: {l, []}
  end

  defmodule Gappy do
    def parts, do: %{lines: Lines}
    def ports, do: %{in: [mounted: :cart_id, unused: :item], out: [total: :summary]}
  end

  defmodule Page do
    def parts, do: %{}
    def ports, do: %{in: [], out: [mounted: :cart_id]}
  end

  test "problems name a mistyped wire, an unbound output, an unbound input and an anonymous function" do
    gappy =
      Binder.story(Gappy, %{lines: nil}, %{
        {:in, :mounted} => [{:input, :lines, &Lines.add/2}],
        {:lines, :summary} => [{:stream, :things}, {:call, fn x -> x end}]
      })

    page = Binder.story(Page, %{}, %{{:page, :mounted} => [{:to, :gappy, :mounted}]})
    problems = Diagram.problems({page, %{gappy: gappy}})

    assert "gappy: in.mounted (cart_id) → lines.add takes item, not cart_id" in problems
    assert "gappy: lines.summary (summary) → a stream takes row_change, not summary" in problems
    assert "gappy: lines.rows is neither bound nor grounded" in problems
    assert "gappy: in.unused is neither bound nor grounded" in problems
    assert "page: gappy.total is neither bound nor grounded" in problems
    assert Enum.any?(problems, &(&1 =~ "anonymous function"))
  end

  test "the diagram is drawn from the value the page runs" do
    chart = Diagram.mermaid(ZeroCoupledWeb.CartPage.composition(1))
    assert chart =~ ~s(edit_cart -->|"removed → capture"| undo)
    assert chart =~ ~s(check_out -->|"pay_requested → request_checkout"| edit_cart)

    {_page, stories} = ZeroCoupledWeb.CartPage.composition(1)
    story = Diagram.mermaid_story(:wishlist, stories.wishlist)
    assert story =~ "wishlist -->|\"taken via AddLine\"| out_added_to_cart((added_to_cart))"
  end
end
