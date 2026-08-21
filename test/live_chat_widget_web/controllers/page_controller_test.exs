defmodule LiveChatWidgetWeb.PageControllerTest do
  use LiveChatWidgetWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Chatlio"
  end
end
