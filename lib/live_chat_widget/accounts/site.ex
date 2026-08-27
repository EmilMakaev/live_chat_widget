defmodule LiveChatWidget.Accounts.Site do
  use Ecto.Schema
  import Ecto.Changeset

  @routing_strategies ~w(broadcast round_robin department)a
  @widget_icons ~w(chat headset smiley bell question)
  @widget_sizes ~w(compact default large)

  schema "sites" do
    field :domain, :string
    field :site_token, :string
    field :routing_strategy, Ecto.Enum, values: @routing_strategies, default: :broadcast
    field :next_visitor_seq, :integer, default: 1
    field :widget_color, :string, default: "#2563eb"
    field :widget_icon, :string, default: "chat"
    field :widget_size, :string, default: "default"

    belongs_to :account, LiveChatWidget.Accounts.Account
    has_many :visitors, LiveChatWidget.Chat.Visitor

    timestamps(type: :utc_datetime_usec)
  end

  def routing_strategies, do: @routing_strategies
  def widget_icons, do: @widget_icons
  def widget_sizes, do: @widget_sizes

  def changeset(site, attrs) do
    site
    |> cast(attrs, [:domain, :routing_strategy, :account_id])
    |> validate_required([:domain, :account_id])
    |> put_site_token()
    |> unique_constraint(:site_token)
    |> foreign_key_constraint(:account_id)
  end

  @doc """
  Widget appearance settings — kept separate from `changeset/2` so the
  "Сайты" settings form can't accidentally touch `domain`/`account_id`.
  """
  def widget_changeset(site, attrs) do
    site
    |> cast(attrs, [:widget_color, :widget_icon, :widget_size])
    |> validate_format(:widget_color, ~r/^#[0-9a-fA-F]{6}$/,
      message: "должен быть в формате #RRGGBB"
    )
    |> validate_inclusion(:widget_icon, @widget_icons)
    |> validate_inclusion(:widget_size, @widget_sizes)
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
