defmodule LiveChatWidget.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(open claimed closed)a

  schema "conversations" do
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :department, :string
    field :last_message_at, :utc_datetime_usec

    belongs_to :site, LiveChatWidget.Accounts.Site
    belongs_to :visitor, LiveChatWidget.Chat.Visitor
    belongs_to :claimed_by_user, LiveChatWidget.Identity.User, foreign_key: :claimed_by_user_id
    has_many :messages, LiveChatWidget.Chat.Message

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:status, :department, :last_message_at, :site_id, :visitor_id])
    |> validate_required([:status, :site_id, :visitor_id])
  end

  def claim_changeset(conversation, user_id) do
    change(conversation, status: :claimed, claimed_by_user_id: user_id)
  end
end
