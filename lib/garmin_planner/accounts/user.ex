defmodule GarminPlanner.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias GarminPlanner.PaceZones.PaceZone
  alias GarminPlanner.Workouts.Workout

  @unit_preferences ~w(miles km)
  @valid_units @unit_preferences

  schema "users" do
    field :name, :string
    field :display_email, :string
    field :unit_preference, :string, default: "miles"
    field :garmin_username, :string

    # Encrypted token fields (binary blobs stored by Cloak)
    field :garmin_oauth1_token, GarminPlanner.Encrypted.Binary
    field :garmin_oauth1_secret, GarminPlanner.Encrypted.Binary
    field :garmin_oauth1_expires_at, :utc_datetime
    field :garmin_oauth2_access_token, GarminPlanner.Encrypted.Binary
    field :garmin_oauth2_refresh_token, GarminPlanner.Encrypted.Binary
    field :garmin_oauth2_expires_at, :utc_datetime
    field :garmin_oauth2_refresh_expires_at, :utc_datetime
    field :garmin_connected_at, :utc_datetime

    has_many :pace_zones, PaceZone
    has_many :workouts, Workout

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating/updating basic user info."
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :display_email, :unit_preference, :garmin_username])
    |> validate_required([:name, :unit_preference])
    |> validate_length(:name, max: 255)
    |> validate_inclusion(:unit_preference, @valid_units)
  end

  @doc "Changeset for storing Garmin tokens after successful auth."
  def garmin_token_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :garmin_username,
      :garmin_oauth1_token,
      :garmin_oauth1_secret,
      :garmin_oauth1_expires_at,
      :garmin_oauth2_access_token,
      :garmin_oauth2_refresh_token,
      :garmin_oauth2_expires_at,
      :garmin_oauth2_refresh_expires_at,
      :garmin_connected_at
    ])
  end

  @doc "Returns true if the user has a connected Garmin account."
  def garmin_connected?(%__MODULE__{garmin_connected_at: nil}), do: false
  def garmin_connected?(%__MODULE__{}), do: true

  @doc "Returns true if the OAuth1 token is expired (or was never set)."
  def oauth1_expired?(%__MODULE__{garmin_oauth1_expires_at: nil}), do: true

  def oauth1_expired?(%__MODULE__{garmin_oauth1_expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end

  def unit_preferences, do: @unit_preferences
end
