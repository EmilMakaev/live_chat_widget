defmodule LiveChatWidget.Repo.Migrations.CustomizeSites do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      remove :name, :string
      add :widget_color, :string, null: false, default: "#2563eb"
      add :widget_icon, :string, null: false, default: "chat"
      add :widget_size, :string, null: false, default: "default"
    end
  end
end
