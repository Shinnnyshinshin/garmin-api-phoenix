defmodule GarminPlanner.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false
      add :display_email, :string
      add :unit_preference, :string, null: false, default: "miles"
      add :garmin_username, :string

      # Encrypted OAuth tokens (stored as binary blobs by Cloak)
      add :garmin_oauth1_token, :binary
      add :garmin_oauth1_secret, :binary
      add :garmin_oauth1_expires_at, :utc_datetime
      add :garmin_oauth2_access_token, :binary
      add :garmin_oauth2_refresh_token, :binary
      add :garmin_oauth2_expires_at, :utc_datetime
      add :garmin_oauth2_refresh_expires_at, :utc_datetime
      add :garmin_connected_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end
  end
end
