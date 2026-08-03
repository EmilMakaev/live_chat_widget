defmodule LiveChatWidget.Repo do
  use Ecto.Repo,
    otp_app: :live_chat_widget,
    adapter: Ecto.Adapters.Postgres
end
