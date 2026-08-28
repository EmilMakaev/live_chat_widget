defmodule LiveChatWidget.Chat do
  @moduledoc """
  Visitor identity, conversations, and messages — the messenger-agnostic
  core that the widget channel, the operator panel, and every messenger
  adapter all read and write through.
  """

  import Ecto.Query, warn: false
  alias LiveChatWidget.Repo
  alias LiveChatWidget.Accounts
  alias LiveChatWidget.Accounts.Site
  alias LiveChatWidget.Chat.{Conversation, Message, MessengerMessageRef, PubSub, Visitor}
  alias LiveChatWidget.Workers.MessengerDispatchWorker

  ## Visitors

  def find_visitor(%Site{} = site, visitor_token) do
    Repo.get_by(Visitor, site_id: site.id, visitor_token: visitor_token)
  end

  def touch_visitor(%Visitor{} = visitor) do
    visitor
    |> Ecto.Changeset.change(last_seen_at: DateTime.utc_now())
    |> Repo.update()
  end

  def create_visitor(%Site{} = site, visitor_token, metadata \\ %{}) do
    %Visitor{}
    |> Visitor.changeset(%{
      site_id: site.id,
      visitor_token: visitor_token,
      display_seq: Accounts.next_visitor_seq!(site),
      metadata: metadata,
      last_seen_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  ## Conversations

  def ensure_conversation(%Visitor{} = visitor) do
    query =
      from c in Conversation,
        where: c.visitor_id == ^visitor.id and c.status in [:open, :claimed],
        order_by: [desc: c.inserted_at],
        limit: 1

    case Repo.one(query) do
      nil ->
        %Conversation{}
        |> Conversation.changeset(%{site_id: visitor.site_id, visitor_id: visitor.id})
        |> Repo.insert()

      conversation ->
        {:ok, conversation}
    end
  end

  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload([:visitor, :site, :claimed_by_user])
  end

  def list_conversations(account_id, opts \\ []) do
    status = Keyword.get(opts, :status)

    Conversation
    |> join(:inner, [c], s in assoc(c, :site))
    |> where([c, s], s.account_id == ^account_id)
    |> maybe_filter_status(status)
    |> order_by([c], desc: c.last_message_at)
    |> preload([:visitor, :site])
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [c], c.status == ^status)

  def list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> preload(:sender_user)
    |> Repo.all()
  end

  ## Inbound (visitor -> operators)

  @doc """
  A visitor sent a message from the widget. Persists it, notifies live
  subscribers (widget echo + operator panel), and fans it out to every
  messenger channel currently responsible for this conversation.
  """
  def receive_visitor_message(%Conversation{} = conversation, body, attachments \\ []) do
    Repo.transaction(fn ->
      with {:ok, message} <-
             insert_message(conversation, %{
               direction: :inbound,
               sender_type: :visitor,
               body: body,
               attachments: attachments
             }),
           {:ok, _} <- touch_conversation(conversation, message) do
        dispatch_to_channels(conversation, message, exclude_channel_id: nil)
        message
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  ## Outbound (operator -> visitor), from the web panel or from a messenger reply

  @doc """
  An operator replied — either from the LiveView panel (`source_channel_id: nil`)
  or from a bound messenger channel (`source_channel_id: channel.id`, so we don't
  echo the message straight back to where it came from).
  """
  def send_operator_message(%Conversation{} = conversation, attrs, opts \\ []) do
    source_channel_id = Keyword.get(opts, :source_channel_id)

    Repo.transaction(fn ->
      with {:ok, message} <-
             insert_message(
               conversation,
               Map.merge(%{direction: :outbound, sender_type: :operator}, attrs)
             ),
           {:ok, conversation} <- touch_conversation(conversation, message),
           {:ok, conversation} <-
             maybe_claim(conversation, attrs[:sender_user_id], source_channel_id) do
        dispatch_to_channels(conversation, message, exclude_channel_id: source_channel_id)
        message
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp maybe_claim(%Conversation{status: :open} = conversation, user_id, source_channel_id) do
    {:ok, conversation} =
      conversation
      |> Conversation.claim_changeset(user_id)
      |> Repo.update()

    broadcast_conversation_update(conversation)
    notify_other_channels_claimed(conversation, source_channel_id)
    {:ok, conversation}
  end

  defp maybe_claim(conversation, _user_id, _source_channel_id), do: {:ok, conversation}

  defp notify_other_channels_claimed(conversation, source_channel_id) do
    site = Accounts.get_site!(conversation.site_id)

    operator_label =
      if conversation.claimed_by_user_id, do: "оператором", else: "другим оператором"

    for channel <-
          Accounts.active_channels(site.account_id,
            department: conversation.department,
            only_user_id: nil
          ),
        channel.id != source_channel_id,
        channel.user_id != conversation.claimed_by_user_id do
      {:ok, notice} =
        insert_message(conversation, %{
          direction: :outbound,
          sender_type: :system,
          body: "Диалог с #{visitor_label(conversation)} перехвачен #{operator_label}."
        })

      enqueue_dispatch(notice, channel)
    end
  end

  defp visitor_label(%Conversation{visitor_id: visitor_id}) do
    case Repo.get(Visitor, visitor_id) do
      nil -> "посетителем"
      visitor -> Visitor.display_name(visitor)
    end
  end

  defp insert_message(conversation, attrs) do
    %Message{}
    |> Message.changeset(Map.put(attrs, :conversation_id, conversation.id))
    |> Repo.insert()
    |> case do
      {:ok, message} = ok ->
        PubSub.broadcast_message(conversation.id, message)
        ok

      error ->
        error
    end
  end

  @preview_length 120

  defp touch_conversation(conversation, message) do
    {:ok, conversation} =
      conversation
      |> Ecto.Changeset.change(
        last_message_at: DateTime.utc_now(),
        last_message_sender_type: message.sender_type,
        last_message_preview: preview(message.body)
      )
      |> Repo.update()

    broadcast_conversation_update(conversation)
    {:ok, conversation}
  end

  defp preview(nil), do: nil

  defp preview(body) do
    body = String.trim(body)

    if String.length(body) > @preview_length do
      String.slice(body, 0, @preview_length) <> "…"
    else
      body
    end
  end

  # Broadcasts the conversation struct we already have in memory (freshly
  # updated by `Repo.update/1` above), fully preloaded — subscribers must
  # not re-fetch it themselves. This call runs inside the same
  # `Repo.transaction` as the message insert, so a re-fetch from another
  # process can race the commit and read the pre-update row; the operator's
  # own LiveView never hit this because handling its own broadcast has to
  # wait for `Repo.transaction/1` to return (i.e. after commit), but a
  # visitor's message — broadcast from the WidgetChannel process — has no
  # such ordering guarantee against a subscriber's independent query.
  defp broadcast_conversation_update(conversation) do
    conversation = Repo.preload(conversation, [:visitor, :site, :claimed_by_user])
    PubSub.broadcast_conversation_update(conversation.site.account_id, conversation)
  end

  defp dispatch_to_channels(conversation, message, exclude_channel_id: exclude_id) do
    only_user_id = if conversation.status == :claimed, do: conversation.claimed_by_user_id
    site = Accounts.get_site!(conversation.site_id)

    site.account_id
    |> Accounts.active_channels(department: conversation.department, only_user_id: only_user_id)
    |> Enum.reject(&(&1.id == exclude_id))
    |> Enum.each(&enqueue_dispatch(message, &1))
  end

  defp enqueue_dispatch(message, channel) do
    %{message_id: message.id, messenger_channel_id: channel.id}
    |> MessengerDispatchWorker.new()
    |> Oban.insert()
  end

  ## Messenger -> conversation reply routing

  def record_messenger_ref(message, channel, external_message_id) do
    %MessengerMessageRef{}
    |> MessengerMessageRef.changeset(%{
      message_id: message.id,
      conversation_id: message.conversation_id,
      messenger_channel_id: channel.id,
      external_message_id: to_string(external_message_id)
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  def find_conversation_by_channel_reply(channel_id, external_message_id) do
    MessengerMessageRef
    |> where(
      [r],
      r.messenger_channel_id == ^channel_id and
        r.external_message_id == ^to_string(external_message_id)
    )
    |> preload(:conversation)
    |> Repo.one()
    |> case do
      nil -> nil
      ref -> ref.conversation
    end
  end
end
