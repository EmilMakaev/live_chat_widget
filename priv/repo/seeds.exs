# mix run priv/repo/seeds.exs
#
# Sets up one demo operator + account + site so the widget and operator
# panel can be tried locally without going through the sign-up flow.

alias LiveChatWidget.{Accounts, Identity, Repo}
alias LiveChatWidget.Identity.User

email = "operator@example.com"
password = "DemoPassword123!"

user =
  case Identity.get_user_by_email(email) do
    nil ->
      {:ok, user} = Identity.register_user(%{email: email})
      user

    user ->
      user
  end

user =
  user
  |> User.password_changeset(%{password: password, password_confirmation: password})
  |> Repo.update!()
  |> User.confirm_changeset()
  |> Repo.update!()

account =
  case Accounts.list_accounts_for_user(user.id) do
    [account | _] ->
      account

    [] ->
      {:ok, account} = Accounts.create_account(%{name: "Demo Company"})
      {:ok, _membership} = Accounts.add_membership(account, user, :owner)
      account
  end

site =
  case Accounts.list_sites(account) do
    [site | _] ->
      site

    [] ->
      {:ok, site} = Accounts.create_site(account, %{"name" => "Demo Site", "domain" => "localhost"})
      site
  end

IO.puts("""

Demo data ready:
  Operator login: #{email} / #{password}
  Account:        #{account.name} (id #{account.id})
  Site token:      #{site.site_token}

Open http://localhost:4000/demo.html to try the widget with this site token.
""")
