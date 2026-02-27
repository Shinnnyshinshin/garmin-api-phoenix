defmodule GarminPlanner.Repo.Migrations.CreatePaceZones do
  use Ecto.Migration

  def change do
    create table(:pace_zones) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :label, :string
      add :min_pace_ms, :integer
      add :max_pace_ms, :integer
      add :color_hex, :string
      add :sort_order, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:pace_zones, [:user_id])
    create unique_index(:pace_zones, [:user_id, :name])
  end
end
