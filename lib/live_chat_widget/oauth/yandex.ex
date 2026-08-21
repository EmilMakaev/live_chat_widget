defmodule LiveChatWidget.OAuth.Yandex do
  @moduledoc """
  Yandex OAuth (Authorization Code flow) — used for operator login only,
  never by widget visitors. See https://yandex.ru/dev/id/doc/ru/ for the
  underlying API.
  """

  require Logger

  @authorize_url "https://oauth.yandex.ru/authorize"
  @token_url "https://oauth.yandex.ru/token"
  @info_url "https://login.yandex.ru/info"

  def authorize_url(state) do
    query =
      URI.encode_query(%{
        response_type: "code",
        client_id: config(:client_id),
        redirect_uri: redirect_uri(),
        state: state
      })

    "#{@authorize_url}?#{query}"
  end

  def exchange_code(code) do
    body = %{
      grant_type: "authorization_code",
      code: code,
      client_id: config(:client_id),
      client_secret: config(:client_secret)
    }

    case Req.post(url: @token_url, form: body) do
      {:ok, %Req.Response{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Yandex token exchange returned #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  def fetch_profile(access_token) do
    case Req.get(url: @info_url, headers: [{"authorization", "OAuth #{access_token}"}]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Yandex login/info returned #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Must exactly match (byte-for-byte) the redirect URI registered in the
  Yandex OAuth app console, so it's derived from the same PUBLIC_BASE_URL
  every other absolute link in the app already uses, not from the request.
  """
  def redirect_uri do
    base_url =
      Application.get_env(:live_chat_widget, :public_base_url) ||
        raise "PUBLIC_BASE_URL is not configured — required for Yandex OAuth redirect_uri"

    String.trim_trailing(base_url, "/") <> "/auth/yandex/callback"
  end

  defp config(key), do: Application.get_env(:live_chat_widget, :yandex)[key]
end
