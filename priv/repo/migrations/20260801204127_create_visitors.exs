defmodule LiveChatWidget.Repo.Migrations.CreateVisitors do
  use Ecto.Migration

  def change do
    create table(:visitors) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :visitor_token, :string, null: false
      add :display_seq, :integer, null: false
      add :metadata, :map, null: false, default: %{}
      add :last_seen_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:visitors, [:visitor_token])
    create index(:visitors, [:site_id])
  end
end
