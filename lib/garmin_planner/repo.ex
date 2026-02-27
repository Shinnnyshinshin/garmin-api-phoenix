defmodule GarminPlanner.Repo do
  use Ecto.Repo,
    otp_app: :garmin_planner,
    adapter: Ecto.Adapters.SQLite3
end
