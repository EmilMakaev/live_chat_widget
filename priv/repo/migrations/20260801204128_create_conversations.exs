defmodule LiveChatWidget.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :visitor_id, references(:visitors, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "open"
      add :claimed_by_user_id, references(:users, on_delete: :nilify_all)
      add :department, :string
      add :last_message_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:conversations, [:site_id, :status])
    create index(:conversations, [:visitor_id])
    create index(:conversations, [:claimed_by_user_id])
  end
end
