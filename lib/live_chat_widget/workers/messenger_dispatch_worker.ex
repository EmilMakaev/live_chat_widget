defmodule LiveChatWidget.Workers.MessengerDispatchWorker do
  @moduledoc """
  Delivers one chat message to one messenger channel, decoupled from the
  request/webhook path so a slow or failing provider (rate limit, outage,
  blocked bot) never blocks the visitor or the operator — Oban retries
  with backoff instead.
  """

  use Oban.Worker,
    queue: :messenger_outbound,
    max_attempts: 8,
    unique: [period: 60, fields: [:args]]

  alias LiveChatWidget.{Accounts, Chat, Repo}
  alias LiveChatWidget.Chat.{Message, Visitor}
  alias LiveChatWidget.Messengers.Registry

  @impl true
  def perform(%Oban.Job{args: %{"message_id" => message_id, "messenger_channel_id" => channel_id}}) do
    message = Repo.get!(Message, message_id)
    channel = Accounts.get_messenger_channel!(channel_id)
    adapter = Registry.adapter_for(channel.type)

    text = adapter.render(message, visitor_label(message))

    case adapter.send_message(channel, text) do
      {:ok, external_message_id} ->
        Chat.record_messenger_ref(message, channel, external_message_id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp visitor_label(message) do
    message = Repo.preload(message, conversation: :visitor)

    case message.conversation.visitor do
      %Visitor{} = visitor -> Visitor.display_name(visitor)
      _ -> "гостем"
    end
  end
end
