defmodule LiveChatWidgetWeb.UserLive.Registration do
  use LiveChatWidgetWeb, :live_view

  alias LiveChatWidget.Identity
  alias LiveChatWidget.Identity.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            Регистрация
            <:subtitle>
              Уже есть аккаунт?
              <.link navigate={~p"/users/log-in"} class="font-semibold text-brand hover:underline">
                Войти
              </.link>
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <.button phx-disable-with="Создаём аккаунт..." class="btn btn-primary w-full">
            Создать аккаунт
          </.button>
        </.form>

        <div class="divider">или</div>

        <.link href={~p"/auth/yandex"} class="btn w-full">
          Зарегистрироваться через Яндекс
        </.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: LiveChatWidgetWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Identity.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok, assign_form(socket, changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Identity.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Identity.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "На #{user.email} отправлено письмо — перейдите по ссылке в нём, чтобы подтвердить аккаунт."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Identity.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
