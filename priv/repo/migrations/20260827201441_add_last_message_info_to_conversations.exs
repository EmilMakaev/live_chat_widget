defmodule LiveChatWidget.Repo.Migrations.AddLastMessageInfoToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :last_message_sender_type, :string
      add :last_message_preview, :string
    end
  end
end
