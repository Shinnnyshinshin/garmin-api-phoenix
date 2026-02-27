defmodule GarminPlannerWeb.PaceZoneController do
  use GarminPlannerWeb, :controller

  alias GarminPlanner.Accounts
  alias GarminPlanner.PaceZones
  alias GarminPlanner.PaceZones.PaceZone

  def index(conn, %{"user_id" => user_id}) do
    user = Accounts.get_user!(user_id)
    zones = PaceZones.list_zones_for_user(user)
    changesets = Enum.map(zones, &PaceZones.change_zone/1)
    render(conn, :index, user: user, zones: zones, changesets: changesets)
  end

  def update_all(conn, %{"user_id" => user_id, "zones" => zones_params}) do
    user = Accounts.get_user!(user_id)
    zones = PaceZones.list_zones_for_user(user)
    unit = String.to_existing_atom(user.unit_preference)

    updates =
      Enum.map(zones, fn zone ->
        raw = Map.get(zones_params, to_string(zone.id), %{})

        min_ms = parse_pace_input(raw["min_pace"], unit)
        max_ms = parse_pace_input(raw["max_pace"], unit)

        attrs = %{
          "min_pace_ms" => min_ms,
          "max_pace_ms" => max_ms,
          "label" => raw["label"]
        }

        {zone.id, attrs}
      end)

    case PaceZones.update_zones_for_user(user, updates) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Pace zones saved.")
        |> redirect(to: ~p"/users/#{user_id}/pace_zones")

      {:error, _} ->
        zones = PaceZones.list_zones_for_user(user)
        changesets = Enum.map(zones, &PaceZones.change_zone/1)

        conn
        |> put_flash(:error, "Could not save zones — please check your input.")
        |> render(:index, user: user, zones: zones, changesets: changesets)
    end
  end

  defp parse_pace_input(nil, _unit), do: nil
  defp parse_pace_input("", _unit), do: nil

  defp parse_pace_input(str, unit) do
    case PaceZone.pace_string_to_ms(str, unit) do
      {:ok, ms} -> ms
      _ -> nil
    end
  end
end
