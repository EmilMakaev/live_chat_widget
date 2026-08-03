defmodule LiveChatWidget.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @directions ~w(inbound outbound)a
  @sender_types ~w(visitor operator system)a

  schema "messages" do
    field :direction, Ecto.Enum, values: @directions
    field :sender_type, Ecto.Enum, values: @sender_types
    field :body, :string
    field :attachments, {:array, :map}, default: []

    belongs_to :conversation, LiveChatWidget.Chat.Conversation
    belongs_to :sender_user, LiveChatWidget.Identity.User, foreign_key: :sender_user_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :direction,
      :sender_type,
      :body,
      :attachments,
      :conversation_id,
      :sender_user_id
    ])
    |> validate_required([:direction, :sender_type, :conversation_id])
    |> validate_body_or_attachments()
  end

  defp validate_body_or_attachments(changeset) do
    body = get_field(changeset, :body)
    attachments = get_field(changeset, :attachments) || []

    if (is_nil(body) or body == "") and attachments == [] do
      add_error(changeset, :body, "can't be blank")
    else
      changeset
    end
  end
end
