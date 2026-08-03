defmodule LiveChatWidget.Repo.Migrations.CreateAccountMemberships do
  use Ecto.Migration

  def change do
    create table(:account_memberships) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "operator"

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:account_memberships, [:account_id, :user_id])
    create index(:account_memberships, [:user_id])
  end
end
