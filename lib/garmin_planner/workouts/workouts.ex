defmodule GarminPlanner.Workouts do
  @moduledoc """
  Context for managing the workout library.
  """

  import Ecto.Query
  alias GarminPlanner.Repo
  alias GarminPlanner.Accounts.User
  alias GarminPlanner.Workouts.Workout

  def list_workouts_for_user(%User{id: user_id}) do
    Workout
    |> where([w], w.user_id == ^user_id)
    |> order_by([w], desc: w.updated_at)
    |> Repo.all()
  end

  def list_workouts_for_user(%User{id: user_id}, tag: tag) when is_binary(tag) do
    Workout
    |> where([w], w.user_id == ^user_id)
    |> where([w], like(w.tags, ^"%#{tag}%"))
    |> order_by([w], desc: w.updated_at)
    |> Repo.all()
  end

  def get_workout!(id), do: Repo.get!(Workout, id)

  def get_workout_for_user!(id, %User{id: user_id}) do
    Repo.get_by!(Workout, id: id, user_id: user_id)
  end

  def create_workout(attrs \\ %{}) do
    %Workout{}
    |> Workout.changeset(attrs)
    |> Repo.insert()
  end

  def update_workout(%Workout{} = workout, attrs) do
    workout
    |> Workout.changeset(attrs)
    |> Repo.update()
  end

  def delete_workout(%Workout{} = workout) do
    Repo.delete(workout)
  end

  def change_workout(%Workout{} = workout, attrs \\ %{}) do
    Workout.changeset(workout, attrs)
  end

  @doc """
  Estimate workout duration in seconds from its step tree and the user's pace zones.
  Caller provides a zone lookup function: (zone_name -> pace_ms | nil).
  """
  def estimate_duration(steps, zone_lookup_fn) when is_list(steps) do
    Enum.reduce(steps, 0, fn step, acc ->
      acc + step_duration(step, zone_lookup_fn)
    end)
  end

  defp step_duration(%{"type" => "repeat", "iterations" => n, "steps" => inner}, lookup) do
    inner_total = estimate_duration(inner, lookup)
    n * inner_total
  end

  defp step_duration(%{"duration_type" => "time", "duration_value" => val}, _lookup)
       when is_number(val),
       do: round(val)

  defp step_duration(
         %{"duration_type" => "distance", "duration_value" => val, "duration_unit" => unit} =
           step,
         lookup
       ) do
    meters = to_meters(val, unit)
    mid_pace_ms = resolve_mid_pace(step, lookup)

    if mid_pace_ms && meters do
      # pace_ms = ms/m, so duration = meters * pace_ms / 1000
      round(meters * mid_pace_ms / 1000)
    else
      # fallback: 5 minutes
      300
    end
  end

  defp step_duration(_, _), do: 300

  defp to_meters(val, "meters"), do: val
  defp to_meters(val, "miles"), do: val * 1609.34
  defp to_meters(val, "km"), do: val * 1000
  defp to_meters(_, _), do: nil

  defp resolve_mid_pace(%{"target" => %{"type" => "zone", "zone_name" => name}}, lookup) do
    case lookup.(name) do
      nil -> nil
      zone -> if zone.min_pace_ms && zone.max_pace_ms, do: div(zone.min_pace_ms + zone.max_pace_ms, 2), else: nil
    end
  end

  defp resolve_mid_pace(_, _), do: nil
end
