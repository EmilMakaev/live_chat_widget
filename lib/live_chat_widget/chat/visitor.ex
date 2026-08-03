defmodule LiveChatWidget.Chat.Visitor do
  use Ecto.Schema
  import Ecto.Changeset

  schema "visitors" do
    field :visitor_token, :string
    field :display_seq, :integer
    field :metadata, :map, default: %{}
    field :last_seen_at, :utc_datetime_usec

    belongs_to :site, LiveChatWidget.Accounts.Site
    has_many :conversations, LiveChatWidget.Chat.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(visitor, attrs) do
    visitor
    |> cast(attrs, [:visitor_token, :display_seq, :metadata, :last_seen_at, :site_id])
    |> validate_required([:visitor_token, :display_seq, :site_id])
    |> unique_constraint(:visitor_token)
  end

  def display_name(%__MODULE__{display_seq: seq}), do: "Гость ##{seq}"
end
