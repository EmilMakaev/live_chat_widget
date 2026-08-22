defmodule LiveChatWidgetWeb.SiteLive.Index do
  @moduledoc """
  Lets an account owner/operator add the websites they want the widget on,
  and gives them the embed snippet (`<script data-site-token="...">`) for
  each one — the piece that was previously only reachable by hand-seeding
  a `Site` row, with no UI at all.
  """

  use LiveChatWidgetWeb, :live_view

  alias LiveChatWidget.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-center justify-between">
        <.header>Сайты</.header>
        <.link navigate={~p"/dashboard"} class="text-sm text-base-content/60 hover:underline">
          ← Диалоги
        </.link>
      </div>

      <form phx-submit="create_site" class="flex flex-col sm:flex-row gap-2">
        <input
          type="text"
          name="name"
          placeholder="Название сайта"
          required
          class="input input-bordered flex-1"
        />
        <input
          type="text"
          name="domain"
          placeholder="example.com"
          required
          class="input input-bordered flex-1"
        />
        <.button variant="primary">Добавить сайт</.button>
      </form>

      <div :if={@sites == []} class="text-sm text-base-content/60">
        Пока нет ни одного сайта.
      </div>

      <div :for={site <- @sites} class="border border-base-300 rounded-lg p-4 space-y-2">
        <div class="flex items-center justify-between gap-2">
          <span class="font-medium">{site.name}</span>
          <span class="text-xs text-base-content/60">{site.domain}</span>
        </div>
        <p class="text-sm text-base-content/60">
          Вставьте этот код перед закрывающим тегом &lt;/body&gt; на вашем сайте:
        </p>
        <pre class="bg-base-200 rounded p-3 text-xs overflow-x-auto"><code>{embed_snippet(site)}</code></pre>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    account = user.id |> Accounts.list_accounts_for_user() |> List.first()

    if account do
      {:ok,
       socket
       |> assign(:account, account)
       |> assign(:sites, Accounts.list_sites(account))
       |> assign(:page_title, "Сайты")}
    else
      {:ok,
       socket
       |> put_flash(:error, "Сначала создайте компанию.")
       |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("create_site", %{"name" => name, "domain" => domain}, socket) do
    case Accounts.create_site(socket.assigns.account, %{"name" => name, "domain" => domain}) do
      {:ok, site} ->
        {:noreply, update(socket, :sites, &(&1 ++ [site]))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Не удалось добавить сайт — проверьте данные.")}
    end
  end

  defp embed_snippet(site) do
    ~s(<script src="#{url(~p"/assets/js/widget.js")}" data-site-token="#{site.site_token}"></script>)
  end
end
