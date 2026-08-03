defmodule LiveChatWidget.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :domain, :string, null: false
      add :site_token, :string, null: false
      add :routing_strategy, :string, null: false, default: "broadcast"
      add :next_visitor_seq, :integer, null: false, default: 1

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sites, [:site_token])
    create index(:sites, [:account_id])
  end
end
