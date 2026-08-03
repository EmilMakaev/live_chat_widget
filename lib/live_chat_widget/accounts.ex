defmodule LiveChatWidget.Accounts do
  @moduledoc """
  Tenants (accounts), their sites, and their connected messenger channels
  (Telegram today, other messengers later behind the same schema/shape).
  """

  import Ecto.Query, warn: false
  alias LiveChatWidget.Repo

  alias LiveChatWidget.Accounts.{Account, Membership, MessengerChannel, Site}

  ## Accounts

  def create_account(attrs) do
    %Account{}
    |> Account.changeset(attrs)
    |> Repo.insert()
  end

  def get_account!(id), do: Repo.get!(Account, id)

  def add_membership(%Account{} = account, user, role \\ :owner) do
    %Membership{}
    |> Membership.changeset(%{account_id: account.id, user_id: user.id, role: role})
    |> Repo.insert()
  end

  def list_accounts_for_user(user_id) do
    Repo.all(
      from a in Account,
        join: m in Membership,
        on: m.account_id == a.id,
        where: m.user_id == ^user_id,
        select: a
    )
  end

  ## Sites

  def create_site(%Account{} = account, attrs) do
    %Site{}
    |> Site.changeset(Map.put(attrs, "account_id", account.id))
    |> Repo.insert()
  end

  def list_sites(%Account{} = account) do
    Repo.all(from s in Site, where: s.account_id == ^account.id, order_by: s.inserted_at)
  end

  def get_site!(id), do: Repo.get!(Site, id)

  def get_site_by_token(token) when is_binary(token) do
    Repo.get_by(Site, site_token: token)
  end

  @doc """
  Atomically claims the next per-site visitor display sequence number
  (used for "Гость #104" style labels) without racing concurrent visitors.
  """
  def next_visitor_seq!(%Site{id: site_id}) do
    {1, [seq]} =
      Repo.update_all(
        from(s in Site, where: s.id == ^site_id, select: s.next_visitor_seq),
        inc: [next_visitor_seq: 1]
      )

    seq
  end

  ## Messenger channels

  def initiate_messenger_connection(%Account{} = account, attrs, user \\ nil) do
    attrs =
      attrs
      |> Map.put("account_id", account.id)
      |> Map.put("user_id", user && user.id)

    %MessengerChannel{}
    |> MessengerChannel.connect_changeset(attrs)
    |> Repo.insert()
  end

  def get_pending_channel_by_connect_code(code) when is_binary(code) do
    Repo.one(
      from c in MessengerChannel,
        where: c.connect_code == ^code and is_nil(c.external_id)
    )
  end

  def bind_messenger_channel(%MessengerChannel{} = channel, attrs) do
    channel
    |> MessengerChannel.bind_changeset(attrs)
    |> Repo.update()
  end

  def get_messenger_channel!(id), do: Repo.get!(MessengerChannel, id)

  def get_messenger_channel_by_external_id(type, external_id) do
    Repo.get_by(MessengerChannel, type: type, external_id: to_string(external_id))
  end

  @doc """
  Channels a message for `account_id` should be routed to.

  * `department` filters channels bound to that department (nil channels match any department).
  * `only_user_id`, when set, restricts routing to a single operator's channels
    (used once a conversation has been claimed by that operator).
  """
  def active_channels(account_id, department: department, only_user_id: only_user_id) do
    MessengerChannel
    |> where([c], c.account_id == ^account_id and c.active == true and not is_nil(c.external_id))
    |> maybe_filter_department(department)
    |> maybe_filter_user(only_user_id)
    |> Repo.all()
  end

  defp maybe_filter_department(query, nil), do: query

  defp maybe_filter_department(query, department) do
    where(query, [c], is_nil(c.department) or c.department == ^department)
  end

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, user_id), do: where(query, [c], c.user_id == ^user_id)
end
