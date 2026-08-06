defmodule LiveChatWidgetWeb.TelegramWebhookController do
  use LiveChatWidgetWeb, :controller

  require Logger

  alias LiveChatWidget.{Accounts, Chat}
  alias LiveChatWidget.Messengers.Telegram

  @doc """
  Telegram POSTs every update here. We must answer fast with 2xx no matter
  what — Telegram retries (and eventually disables) a webhook that errors
  or times out, so anything not immediately actionable is just ignored.
  """
  def create(conn, params) do
    with :ok <- Telegram.verify_webhook(conn),
         {:ok, event} <- Telegram.parse_webhook(params) do
      handle_event(event)
    else
      {:error, reason} ->
        Logger.warning("Rejected Telegram webhook: #{inspect(reason)}")

      :ignore ->
        :ok
    end

    send_resp(conn, 200, "")
  end

  defp handle_event(%{kind: :connect} = event) do
    case Accounts.get_pending_channel_by_connect_code(event.connect_code) do
      nil ->
        Telegram.send_message(%{external_id: event.external_id}, """
        Код приглашения недействителен или уже использован. \
        Получите новую ссылку в личном кабинете и попробуйте снова.
        """)

      channel ->
        {:ok, channel} =
          Accounts.bind_messenger_channel(channel, %{external_id: event.external_id})

        Telegram.send_message(
          channel,
          "Готово! Теперь сообщения посетителей сайта будут приходить сюда — просто отвечайте на них (Reply)."
        )
    end
  end

  defp handle_event(%{kind: :reply} = event) do
    case Accounts.get_messenger_channel_by_external_id(:telegram, event.external_id) do
      nil ->
        :ignore

      channel ->
        case Chat.find_conversation_by_channel_reply(
               channel.id,
               event.reply_to_external_message_id
             ) do
          nil ->
            Telegram.send_message(
              channel,
              "Не удалось найти диалог для этого сообщения — возможно, он уже закрыт."
            )

          conversation ->
            Chat.send_operator_message(
              conversation,
              %{sender_user_id: channel.user_id, body: event.text},
              source_channel_id: channel.id
            )
        end
    end
  end
end
