defmodule Mix.Tasks.Telegram.Webhook do
  @moduledoc """
  Registers the app's `/webhooks/telegram` endpoint as the bot's webhook.

      mix telegram.webhook https://your-ngrok-or-prod-domain

  Run this again whenever your public URL changes (e.g. a new ngrok tunnel).
  """
  @shortdoc "Sets the Telegram bot webhook to <base_url>/webhooks/telegram"

  use Mix.Task

  @impl true
  def run([base_url]) do
    Mix.Task.run("app.start")

    url = String.trim_trailing(base_url, "/") <> "/webhooks/telegram"

    case LiveChatWidget.Messengers.Telegram.set_webhook(url) do
      {:ok, %{"ok" => true}} -> Mix.shell().info("Webhook set to #{url}")
      {:ok, body} -> Mix.shell().error("Telegram rejected the webhook: #{inspect(body)}")
      {:error, reason} -> Mix.shell().error("Request failed: #{inspect(reason)}")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix telegram.webhook https://your-domain")
  end
end
