defmodule LiveChatWidget.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :direction, :string, null: false
      add :sender_type, :string, null: false
      add :sender_user_id, references(:users, on_delete: :nilify_all)
      add :body, :text
      add :attachments, {:array, :map}, null: false, default: []

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:messages, [:conversation_id, :inserted_at])
  end
end
