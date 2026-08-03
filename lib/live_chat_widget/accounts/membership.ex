defmodule LiveChatWidget.Accounts.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(owner admin operator)a

  schema "account_memberships" do
    field :role, Ecto.Enum, values: @roles, default: :operator

    belongs_to :account, LiveChatWidget.Accounts.Account
    belongs_to :user, LiveChatWidget.Identity.User

    timestamps(type: :utc_datetime_usec)
  end

  def roles, do: @roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :account_id, :user_id])
    |> validate_required([:role, :account_id, :user_id])
    |> unique_constraint([:account_id, :user_id])
  end
end
