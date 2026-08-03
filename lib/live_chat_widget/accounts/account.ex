defmodule LiveChatWidget.Accounts.Account do
  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :name, :string

    has_many :memberships, LiveChatWidget.Accounts.Membership
    has_many :sites, LiveChatWidget.Accounts.Site
    has_many :messenger_channels, LiveChatWidget.Accounts.MessengerChannel

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 160)
  end
end
