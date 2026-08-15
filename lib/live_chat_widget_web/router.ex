defmodule LiveChatWidgetWeb.Router do
  use LiveChatWidgetWeb, :router

  import LiveChatWidgetWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LiveChatWidgetWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LiveChatWidgetWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/webhooks", LiveChatWidgetWeb do
    pipe_through :api

    post "/telegram", TelegramWebhookController, :create
  end

  # LiveDashboard shows system-wide internals (every process, every Ecto
  # query across every tenant) — gated to the platform admin flag, not
  # tied to any tenant's own "admin" role, and available in prod on purpose
  # (not just :dev_routes) since that's exactly where you need it.
  import Phoenix.LiveDashboard.Router

  scope "/admin", LiveChatWidgetWeb do
    pipe_through [:browser, :require_authenticated_user, :require_admin_user]

    live_dashboard "/dashboard", metrics: LiveChatWidgetWeb.Telemetry
  end

  # Swoosh mailbox preview stays dev-only — prod uses a real mailer, there's
  # nothing local to preview.
  if Application.compile_env(:live_chat_widget, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", LiveChatWidgetWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{LiveChatWidgetWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", OperatorLive.Dashboard, :index
      live "/dashboard/:id", OperatorLive.Dashboard, :show
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", LiveChatWidgetWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{LiveChatWidgetWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
