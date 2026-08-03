defmodule LiveChatWidget.Repo.Migrations.AlterMessengerChannelsExternalIdNullable do
  use Ecto.Migration

  def change do
    alter table(:messenger_channels) do
      modify :external_id, :string, null: true
    end
  end
end
