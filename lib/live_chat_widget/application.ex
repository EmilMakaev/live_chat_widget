defmodule LiveChatWidget.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LiveChatWidgetWeb.Telemetry,
      LiveChatWidget.Repo,
      {DNSCluster, query: Application.get_env(:live_chat_widget, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LiveChatWidget.PubSub},
      LiveChatWidget.RateLimit,
      {Oban, Application.fetch_env!(:live_chat_widget, Oban)},
      # Start to serve requests, typically the last entry
      LiveChatWidgetWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LiveChatWidget.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LiveChatWidgetWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
