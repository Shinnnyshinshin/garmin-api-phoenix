defmodule GarminPlanner.Accounts do
  @moduledoc """
  Context for managing users and their Garmin account connections.
  """

  alias GarminPlanner.Repo
  alias GarminPlanner.Accounts.User
  alias GarminPlanner.PaceZones

  def list_users do
    Repo.all(User)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} = result ->
        PaceZones.seed_default_zones(user)
        result

      error ->
        error
    end
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc "Store Garmin OAuth tokens on the user after a successful auth flow."
  def connect_garmin(%User{} = user, token_attrs) do
    user
    |> User.garmin_token_changeset(token_attrs)
    |> Repo.update()
  end

  @doc "Remove Garmin connection from a user."
  def disconnect_garmin(%User{} = user) do
    user
    |> User.garmin_token_changeset(%{
      garmin_oauth1_token: nil,
      garmin_oauth1_secret: nil,
      garmin_oauth1_expires_at: nil,
      garmin_oauth2_access_token: nil,
      garmin_oauth2_refresh_token: nil,
      garmin_oauth2_expires_at: nil,
      garmin_oauth2_refresh_expires_at: nil,
      garmin_connected_at: nil
    })
    |> Repo.update()
  end
end
