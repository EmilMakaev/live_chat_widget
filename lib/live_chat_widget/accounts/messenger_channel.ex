defmodule LiveChatWidget.Accounts.MessengerChannel do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(telegram)a

  schema "messenger_channels" do
    field :type, Ecto.Enum, values: @types
    field :external_id, :string
    field :department, :string
    field :config, :map, default: %{}
    field :active, :boolean, default: true
    field :connect_code, :string

    belongs_to :account, LiveChatWidget.Accounts.Account
    belongs_to :user, LiveChatWidget.Identity.User

    timestamps(type: :utc_datetime_usec)
  end

  def types, do: @types

  def connect_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:type, :department, :account_id, :user_id])
    |> validate_required([:type, :account_id])
    |> put_connect_code()
    |> unique_constraint(:connect_code)
  end

  def bind_changeset(channel, attrs) do
    channel
    |> cast(attrs, [:external_id, :active])
    |> validate_required([:external_id])
    |> unique_constraint([:type, :external_id])
  end

  defp put_connect_code(changeset) do
    put_change(changeset, :connect_code, generate_code())
  end

  defp generate_code do
    :crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false)
  end
end
