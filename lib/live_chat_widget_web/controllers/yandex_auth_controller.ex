defmodule LiveChatWidgetWeb.YandexAuthController do
  use LiveChatWidgetWeb, :controller

  alias LiveChatWidget.Identity
  alias LiveChatWidget.OAuth.Yandex
  alias LiveChatWidgetWeb.UserAuth

  require Logger

  def request(conn, _params) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    conn
    |> put_session(:yandex_oauth_state, state)
    |> redirect(external: Yandex.authorize_url(state))
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    expected_state = get_session(conn, :yandex_oauth_state)

    if is_binary(expected_state) and Plug.Crypto.secure_compare(state, expected_state) do
      conn
      |> delete_session(:yandex_oauth_state)
      |> log_in_via_yandex(code)
    else
      login_error(conn, "Не удалось подтвердить запрос на вход через Яндекс — попробуйте снова.")
    end
  end

  def callback(conn, %{"error" => error} = params) do
    Logger.info("Yandex OAuth declined: #{error} (#{inspect(params)})")
    login_error(conn, "Вход через Яндекс отменён.")
  end

  def callback(conn, _params) do
    login_error(conn, "Не удалось войти через Яндекс.")
  end

  defp log_in_via_yandex(conn, code) do
    with {:ok, access_token} <- Yandex.exchange_code(code),
         {:ok, profile} <- Yandex.fetch_profile(access_token),
         {:ok, email} <- yandex_email(profile),
         {:ok, user} <- Identity.get_or_register_user_from_yandex(email) do
      conn
      |> put_flash(:info, "С возвращением!")
      |> UserAuth.log_in_user(user)
    else
      {:error, reason} ->
        Logger.warning("Yandex OAuth login failed: #{inspect(reason)}")

        login_error(
          conn,
          "Не удалось войти через Яндекс. Попробуйте снова или используйте email."
        )
    end
  end

  defp yandex_email(%{"default_email" => email}) when is_binary(email) and email != "",
    do: {:ok, email}

  defp yandex_email(%{"emails" => [email | _]}) when is_binary(email) and email != "",
    do: {:ok, email}

  defp yandex_email(_profile), do: {:error, :no_email_from_yandex}

  defp login_error(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/users/log-in")
  end
end
