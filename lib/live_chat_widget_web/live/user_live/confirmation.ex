defmodule LiveChatWidgetWeb.UserLive.Confirmation do
  use LiveChatWidgetWeb, :live_view

  alias LiveChatWidget.Identity

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>Здравствуйте, {@user.email}</.header>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with="Подтверждаем..."
            class="btn btn-primary w-full"
          >
            Подтвердить и оставаться в системе
          </.button>
          <.button phx-disable-with="Подтверждаем..." class="btn btn-primary btn-soft w-full mt-2">
            Подтвердить и войти только сейчас
          </.button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope do %>
            <.button phx-disable-with="Входим..." class="btn btn-primary w-full">
              Войти
            </.button>
          <% else %>
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Входим..."
              class="btn btn-primary w-full"
            >
              Оставаться в системе на этом устройстве
            </.button>
            <.button phx-disable-with="Входим..." class="btn btn-primary btn-soft w-full mt-2">
              Войти только сейчас
            </.button>
          <% end %>
        </.form>

        <p :if={!@user.confirmed_at} class="alert alert-outline mt-8">
          Совет: если вам удобнее с паролем, его можно включить в настройках аккаунта.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Identity.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Ссылка для входа недействительна или устарела.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
