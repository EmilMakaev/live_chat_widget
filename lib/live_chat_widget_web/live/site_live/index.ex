defmodule LiveChatWidgetWeb.SiteLive.Index do
  @moduledoc """
  Lets an account owner/operator add the websites they want the widget on,
  and gives them the embed snippet (`<script data-site-token="...">`) for
  each one — the piece that was previously only reachable by hand-seeding
  a `Site` row, with no UI at all.
  """

  use LiveChatWidgetWeb, :live_view

  alias LiveChatWidget.Accounts
  alias LiveChatWidget.Accounts.Site

  @icon_labels %{
    "chat" => "Диалог",
    "headset" => "Наушники",
    "smiley" => "Смайл",
    "bell" => "Колокольчик",
    "question" => "Вопрос"
  }
  @size_labels %{
    "compact" => "Компактный",
    "default" => "Обычный",
    "large" => "Крупный"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-center justify-between">
        <.header>Сайты</.header>
        <.link
          :if={@sites != []}
          navigate={~p"/dashboard"}
          class="text-sm text-base-content/60 hover:underline"
        >
          ← Диалоги
        </.link>
      </div>

      <form phx-submit="create_site" class="flex flex-col sm:flex-row gap-2">
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

      <div :for={site <- @sites} class="border border-base-300 rounded-lg p-4 space-y-3">
        <div class="flex items-center justify-between gap-2">
          <span class="font-medium">{site.domain}</span>
          <span class="text-xs text-base-content/60 font-mono">{site.site_token}</span>
        </div>

        <p class="text-sm text-base-content/60">
          Вставьте этот код перед закрывающим тегом &lt;/body&gt; на вашем сайте:
        </p>
        <pre class="bg-base-200 rounded p-3 text-xs overflow-x-auto"><code>{embed_snippet(site)}</code></pre>

        <details class="pt-1">
          <summary class="text-sm text-base-content/70 cursor-pointer select-none">
            Внешний вид виджета
          </summary>
          <form
            phx-submit="update_widget"
            phx-value-site_id={site.id}
            class="mt-3 flex flex-wrap items-end gap-4"
          >
            <input type="hidden" name="site_id" value={site.id} />

            <label class="flex flex-col gap-1 text-sm">
              <span class="text-base-content/60">Цвет</span>
              <input
                type="color"
                name="widget_color"
                value={site.widget_color}
                class="h-9 w-14 rounded border border-base-300 bg-transparent p-1"
              />
            </label>

            <label class="flex flex-col gap-1 text-sm">
              <span class="text-base-content/60">Иконка</span>
              <select name="widget_icon" class="select select-bordered select-sm">
                <option
                  :for={key <- Site.widget_icons()}
                  value={key}
                  selected={key == site.widget_icon}
                >
                  {@icon_labels[key]}
                </option>
              </select>
            </label>

            <label class="flex flex-col gap-1 text-sm">
              <span class="text-base-content/60">Размер</span>
              <select name="widget_size" class="select select-bordered select-sm">
                <option
                  :for={key <- Site.widget_sizes()}
                  value={key}
                  selected={key == site.widget_size}
                >
                  {@size_labels[key]}
                </option>
              </select>
            </label>

            <.button variant="primary" class="btn-sm">Сохранить</.button>
          </form>
        </details>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    account = Accounts.get_or_create_account_for_user(socket.assigns.current_scope.user)

    {:ok,
     socket
     |> assign(:account, account)
     |> assign(:sites, Accounts.list_sites(account))
     |> assign(:page_title, "Сайты")
     |> assign(:icon_labels, @icon_labels)
     |> assign(:size_labels, @size_labels)}
  end

  @impl true
  def handle_event("create_site", %{"domain" => domain}, socket) do
    case Accounts.create_site(socket.assigns.account, %{"domain" => domain}) do
      {:ok, site} ->
        {:noreply, update(socket, :sites, &(&1 ++ [site]))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Не удалось добавить сайт — проверьте данные.")}
    end
  end

  def handle_event("update_widget", %{"site_id" => site_id} = params, socket) do
    site = Enum.find(socket.assigns.sites, &(&1.id == String.to_integer(site_id)))

    case site && Accounts.update_site_widget(site, params) do
      {:ok, updated_site} ->
        {:noreply,
         update(socket, :sites, fn sites ->
           Enum.map(sites, &if(&1.id == updated_site.id, do: updated_site, else: &1))
         end)}

      _ ->
        {:noreply, put_flash(socket, :error, "Не удалось сохранить настройки виджета.")}
    end
  end

  defp embed_snippet(site) do
    ~s(<script src="#{url(~p"/assets/js/widget.js")}" data-site-token="#{site.site_token}"></script>)
  end
end
