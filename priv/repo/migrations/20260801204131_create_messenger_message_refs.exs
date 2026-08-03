defmodule LiveChatWidget.Repo.Migrations.CreateMessengerMessageRefs do
  use Ecto.Migration

  def change do
    create table(:messenger_message_refs) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :messenger_channel_id, references(:messenger_channels, on_delete: :delete_all),
        null: false

      add :external_message_id, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:messenger_message_refs, [:messenger_channel_id, :external_message_id])
    create index(:messenger_message_refs, [:conversation_id])
  end
end
