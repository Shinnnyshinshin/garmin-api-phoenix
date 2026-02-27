# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :garmin_planner,
  ecto_repos: [GarminPlanner.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :garmin_planner, GarminPlannerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GarminPlannerWeb.ErrorHTML, json: GarminPlannerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GarminPlanner.PubSub,
  live_view: [signing_salt: "gviF/BR6"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  garmin_planner: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  garmin_planner: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Cloak vault — cipher key loaded at runtime from GARMIN_PLANNER_ENCRYPTION_KEY env var.
# See config/runtime.exs for production config.
# The key below is a placeholder overridden in dev/test/prod via runtime.exs.
config :garmin_planner, GarminPlanner.Vault, ciphers: []

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
