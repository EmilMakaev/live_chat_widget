defmodule LiveChatWidget.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :name, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
