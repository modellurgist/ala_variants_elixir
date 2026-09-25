defmodule ZeroCoupledWeb.PageControllerTest do
  use ZeroCoupledWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Welcome to ZeroCoupled!"
  end
end
