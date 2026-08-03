defmodule LiveChatWidget.Chat.PubSub do
  @moduledoc """
  Topic naming + broadcast helpers shared by the widget channel, the
  operator LiveView panel, and the messenger dispatch workers.
  """

  alias Phoenix.PubSub

  def conversation_topic(conversation_id), do: "conversation:#{conversation_id}"
  def account_topic(account_id), do: "account:#{account_id}:conversations"

  def subscribe(topic), do: PubSub.subscribe(LiveChatWidget.PubSub, topic)
  def unsubscribe(topic), do: PubSub.unsubscribe(LiveChatWidget.PubSub, topic)

  def broadcast_message(conversation_id, message) do
    PubSub.broadcast(
      LiveChatWidget.PubSub,
      conversation_topic(conversation_id),
      {:chat_message, message}
    )
  end

  def broadcast_conversation_update(account_id, conversation) do
    PubSub.broadcast(
      LiveChatWidget.PubSub,
      account_topic(account_id),
      {:conversation_updated, conversation}
    )
  end
end
