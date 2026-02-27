defmodule GarminPlannerWeb.Router do
  use GarminPlannerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GarminPlannerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GarminPlannerWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Users
    resources "/users", UserController, except: [:show] do
      # Garmin auth
      get "/garmin/connect", GarminAuthController, :new, as: :garmin_connect
      post "/garmin/connect", GarminAuthController, :create, as: :garmin_connect
      delete "/garmin/disconnect", GarminAuthController, :delete, as: :garmin_disconnect

      # Pace zones
      get "/pace_zones", PaceZoneController, :index, as: :pace_zones
      put "/pace_zones", PaceZoneController, :update_all, as: :pace_zones
    end

    # Workout library
    get "/workouts", WorkoutController, :index
    live "/workouts/new", WorkoutBuilderLive, :new
    live "/workouts/:id/edit", WorkoutBuilderLive, :edit
    delete "/workouts/:id", WorkoutController, :delete
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:garmin_planner, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: GarminPlannerWeb.Telemetry
    end
  end
end
