defmodule LiveChatWidgetWeb.PageController do
  use LiveChatWidgetWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
