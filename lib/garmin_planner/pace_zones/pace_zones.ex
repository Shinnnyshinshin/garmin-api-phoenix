defmodule GarminPlanner.PaceZones do
  @moduledoc """
  Context for managing per-user pace zones.
  """

  import Ecto.Query
  alias GarminPlanner.Repo
  alias GarminPlanner.Accounts.User
  alias GarminPlanner.PaceZones.PaceZone

  def list_zones_for_user(%User{id: user_id}) do
    PaceZone
    |> where([z], z.user_id == ^user_id)
    |> order_by([z], z.sort_order)
    |> Repo.all()
  end

  def get_zone!(id), do: Repo.get!(PaceZone, id)

  def get_zone_by_name(%User{id: user_id}, name) do
    Repo.get_by(PaceZone, user_id: user_id, name: name)
  end

  def create_zone(attrs) do
    %PaceZone{}
    |> PaceZone.changeset(attrs)
    |> Repo.insert()
  end

  def update_zone(%PaceZone{} = zone, attrs) do
    zone
    |> PaceZone.changeset(attrs)
    |> Repo.update()
  end

  def delete_zone(%PaceZone{} = zone) do
    Repo.delete(zone)
  end

  def change_zone(%PaceZone{} = zone, attrs \\ %{}) do
    PaceZone.changeset(zone, attrs)
  end

  @doc """
  Seed default pace zones for a newly connected user.
  Skips zones that already exist (idempotent).
  """
  def seed_default_zones(%User{id: user_id}) do
    PaceZone.default_zones()
    |> Enum.each(fn zone_attrs ->
      attrs = Map.put(zone_attrs, :user_id, user_id)

      case Repo.get_by(PaceZone, user_id: user_id, name: zone_attrs.name) do
        nil ->
          %PaceZone{}
          |> PaceZone.changeset(attrs)
          |> Repo.insert()

        _existing ->
          :ok
      end
    end)
  end

  @doc """
  Update all zones for a user in a single transaction.
  Accepts a list of {zone_id, attrs} tuples.
  """
  def update_zones_for_user(%User{id: user_id}, zone_updates) do
    Repo.transaction(fn ->
      Enum.each(zone_updates, fn {zone_id, attrs} ->
        zone = Repo.get_by!(PaceZone, id: zone_id, user_id: user_id)

        zone
        |> PaceZone.changeset(attrs)
        |> Repo.update!()
      end)
    end)
  end
end
