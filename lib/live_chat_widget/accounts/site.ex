defmodule LiveChatWidget.Accounts.Site do
  use Ecto.Schema
  import Ecto.Changeset

  @routing_strategies ~w(broadcast round_robin department)a

  schema "sites" do
    field :name, :string
    field :domain, :string
    field :site_token, :string
    field :routing_strategy, Ecto.Enum, values: @routing_strategies, default: :broadcast
    field :next_visitor_seq, :integer, default: 1

    belongs_to :account, LiveChatWidget.Accounts.Account
    has_many :visitors, LiveChatWidget.Chat.Visitor

    timestamps(type: :utc_datetime_usec)
  end

  def routing_strategies, do: @routing_strategies

  def changeset(site, attrs) do
    site
    |> cast(attrs, [:name, :domain, :routing_strategy, :account_id])
    |> validate_required([:name, :domain, :account_id])
    |> put_site_token()
    |> unique_constraint(:site_token)
    |> foreign_key_constraint(:account_id)
  end

  defp put_site_token(changeset) do
    if get_field(changeset, :site_token) do
      changeset
    else
      put_change(changeset, :site_token, generate_token())
    end
  end

  defp generate_token do
    "site_" <> (:crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false))
  end
end
