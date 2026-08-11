defmodule LiveChatWidgetWeb.PageController do
  use LiveChatWidgetWeb, :controller

  def home(conn, _params) do
    if conn.assigns.current_scope do
      redirect(conn, to: ~p"/dashboard")
    else
      render(conn, :home)
    end
  end
end
