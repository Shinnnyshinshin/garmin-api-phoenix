defmodule GarminPlannerWeb.WorkoutController do
  use GarminPlannerWeb, :controller

  import Ecto.Query
  alias GarminPlanner.{Repo, Workouts}
  alias GarminPlanner.Workouts.Workout

  # Show all workouts across all users (no auth — trusted local network).
  def index(conn, params) do
    workouts = list_workouts(params)
    render(conn, :index, workouts: workouts, filter_tag: Map.get(params, "tag"))
  end

  def delete(conn, %{"id" => id}) do
    workout = Workouts.get_workout!(id)
    {:ok, _} = Workouts.delete_workout(workout)

    conn
    |> put_flash(:info, "Workout deleted.")
    |> redirect(to: ~p"/workouts")
  end

  defp list_workouts(%{"tag" => tag}) when tag != "" do
    tag_filter = "%#{tag}%"
    Repo.all(from w in Workout, where: like(w.tags, ^tag_filter), order_by: [desc: w.updated_at])
  end

  defp list_workouts(_) do
    Repo.all(from w in Workout, order_by: [desc: w.updated_at])
  end
end
