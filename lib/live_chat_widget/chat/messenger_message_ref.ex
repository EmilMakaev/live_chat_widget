defmodule LiveChatWidget.Chat.MessengerMessageRef do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messenger_message_refs" do
    field :external_message_id, :string

    belongs_to :message, LiveChatWidget.Chat.Message
    belongs_to :conversation, LiveChatWidget.Chat.Conversation
    belongs_to :messenger_channel, LiveChatWidget.Accounts.MessengerChannel

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(ref, attrs) do
    ref
    |> cast(attrs, [:external_message_id, :message_id, :conversation_id, :messenger_channel_id])
    |> validate_required([
      :external_message_id,
      :message_id,
      :conversation_id,
      :messenger_channel_id
    ])
    |> unique_constraint([:messenger_channel_id, :external_message_id])
  end
end
