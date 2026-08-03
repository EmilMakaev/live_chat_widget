defmodule LiveChatWidget.Repo.Migrations.CreateMessengerChannels do
  use Ecto.Migration

  def change do
    create table(:messenger_channels) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :type, :string, null: false
      add :external_id, :string, null: false
      add :department, :string
      add :config, :map, null: false, default: %{}
      add :active, :boolean, null: false, default: true
      add :connect_code, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:messenger_channels, [:type, :external_id])
    create unique_index(:messenger_channels, [:connect_code])
    create index(:messenger_channels, [:account_id])
    create index(:messenger_channels, [:user_id])
  end
end
