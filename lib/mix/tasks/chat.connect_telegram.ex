defmodule Mix.Tasks.Chat.ConnectTelegram do
  @moduledoc """
  Generates a Telegram connect deep-link for an operator (stands in for the
  "Подключить Telegram" button in the client's dashboard, which doesn't have
  a UI yet — see README "Известные ограничения").

      mix chat.connect_telegram operator@example.com

  Send the printed link to the operator; opening it and pressing Start in
  Telegram binds that chat to receive messages for their account.
  """
  @shortdoc "Prints a Telegram connect link for the given operator's account"

  use Mix.Task

  alias LiveChatWidget.{Accounts, Identity}

  @impl true
  def run([email]) do
    Mix.Task.run("app.start")

    with %{} = user <- Identity.get_user_by_email(email) || {:error, :no_such_user},
         [account | _] <- Accounts.list_accounts_for_user(user.id) do
      {:ok, channel} =
        Accounts.initiate_messenger_connection(account, %{"type" => "telegram"}, user)

      bot_username = telegram_username()

      Mix.shell().info("""

      Account: #{account.name}
      Connect link: https://t.me/#{bot_username}?start=connect_#{channel.connect_code}
      """)
    else
      {:error, :no_such_user} -> Mix.shell().error("No user with email #{email}")
      [] -> Mix.shell().error("#{email} has no account yet")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix chat.connect_telegram operator@example.com")
  end

  defp telegram_username do
    case LiveChatWidget.Messengers.Telegram.get_me() do
      {:ok, %{"result" => %{"username" => username}}} -> username
      _ -> "<your_bot_username>"
    end
  end
end
