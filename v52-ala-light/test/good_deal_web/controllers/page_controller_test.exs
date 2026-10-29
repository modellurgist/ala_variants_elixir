defmodule GoodDealWeb.PageControllerTest do
  use GoodDealWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Welcome to GoodDeal!"
  end
end
