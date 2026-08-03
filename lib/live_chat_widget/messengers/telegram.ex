defmodule LiveChatWidget.Messengers.Telegram do
  @moduledoc """
  Telegram Bot API adapter: https://core.telegram.org/bots/api

  One bot token serves every tenant. Which company/operator a chat belongs
  to is resolved via `messenger_channels.external_id` (the Telegram chat_id),
  bound once through the `/start connect_<code>` deep-link flow.
  """

  @behaviour LiveChatWidget.Messengers.Adapter

  require Logger

  @impl true
  def send_message(channel, text) do
    case request("sendMessage", %{chat_id: channel.external_id, text: text}) do
      {:ok, %{"result" => %{"message_id" => message_id}}} ->
        {:ok, to_string(message_id)}

      {:ok, %{"ok" => false, "description" => description}} ->
        {:error, description}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def verify_webhook(conn) do
    expected = config(:webhook_secret)
    got = conn |> Plug.Conn.get_req_header("x-telegram-bot-api-secret-token") |> List.first()

    cond do
      is_nil(expected) or expected == "" ->
        {:error, :webhook_secret_not_configured}

      is_binary(got) and Plug.Crypto.secure_compare(got, expected) ->
        :ok

      true ->
        {:error, :invalid_secret_token}
    end
  end

  @impl true
  def parse_webhook(%{"message" => message}) do
    text = Map.get(message, "text", "")
    chat_id = get_in(message, ["chat", "id"])

    cond do
      match = Regex.run(~r/^\/start connect_(\S+)/, text) ->
        [_, code] = match

        {:ok,
         %LiveChatWidget.Messengers.IncomingEvent{
           kind: :connect,
           connect_code: code,
           external_id: to_string(chat_id),
           meta: %{
             username: get_in(message, ["from", "username"]),
             first_name: get_in(message, ["from", "first_name"])
           }
         }}

      reply_to = message["reply_to_message"] ->
        {:ok,
         %LiveChatWidget.Messengers.IncomingEvent{
           kind: :reply,
           external_id: to_string(chat_id),
           reply_to_external_message_id: to_string(reply_to["message_id"]),
           text: text
         }}

      true ->
        :ignore
    end
  end

  def parse_webhook(_other), do: :ignore

  @impl true
  def render(%{sender_type: :visitor} = message, visitor_label) do
    "\u{1F4E9} Новое сообщение с сайта!\nИмя: #{visitor_label}\nТекст: #{message.body}"
  end

  def render(%{sender_type: :system} = message, _visitor_label), do: message.body
  def render(%{sender_type: :operator} = message, _visitor_label), do: message.body

  def set_webhook(url) do
    request("setWebhook", %{url: url, secret_token: config(:webhook_secret)})
  end

  def get_me, do: request("getMe", %{})

  defp request(method, params) do
    token = config(:bot_token)

    case Req.post(url: "https://api.telegram.org/bot#{token}/#{method}", json: params) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Telegram API #{method} returned #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp config(key), do: Application.get_env(:live_chat_widget, :telegram)[key]
end
