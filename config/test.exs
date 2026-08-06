import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :live_chat_widget, LiveChatWidget.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "live_chat_widget_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :live_chat_widget, LiveChatWidgetWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "jq24RxecbxCj9qgtBnuTIvXgUHWR5SP1NjnMYNAWQhttEEryA5ODukuN8fxu5Thg",
  server: false

# In test we don't send emails
config :live_chat_widget, LiveChatWidget.Mailer, adapter: Swoosh.Adapters.Test

# Oban's real queues/plugins/peer election need a live DB connection outside
# any test's sandbox transaction — `:manual` disables all of that so tests
# control job execution explicitly (Oban.Testing / Oban.drain_queue).
config :live_chat_widget, Oban, testing: :manual

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
