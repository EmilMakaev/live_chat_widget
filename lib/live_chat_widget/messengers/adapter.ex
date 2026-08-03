defmodule LiveChatWidget.Messengers.Adapter do
  @moduledoc """
  Behaviour every messenger integration (Telegram, and later WhatsApp/Slack/Viber)
  implements. The rest of the app (Chat context, dispatch worker, webhook
  controller) only ever talks to this interface, never to a specific API —
  adding a messenger means writing one new module, not touching existing ones.
  """

  alias LiveChatWidget.Accounts.MessengerChannel

  @doc "Send text to the bound external chat/channel. Returns the provider's message id so replies can be mapped back."
  @callback send_message(channel :: MessengerChannel.t(), text :: String.t()) ::
              {:ok, external_message_id :: String.t()} | {:error, term()}

  @doc "Verify an inbound webhook request actually came from the provider."
  @callback verify_webhook(conn :: Plug.Conn.t()) :: :ok | {:error, term()}

  @doc "Turn a raw webhook payload into a normalized event the rest of the app understands."
  @callback parse_webhook(payload :: map()) ::
              {:ok, LiveChatWidget.Messengers.IncomingEvent.t()} | :ignore | {:error, term()}

  @doc "Format an app message for this provider (e.g. Telegram plain text vs. a Slack block)."
  @callback render(message :: LiveChatWidget.Chat.Message.t(), visitor_label :: String.t()) ::
              String.t()
end
