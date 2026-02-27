defmodule GarminPlanner.Repo.Migrations.CreateWorkouts do
  use Ecto.Migration

  def change do
    create table(:workouts) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :sport_type, :string, null: false, default: "running"
      add :estimated_duration_secs, :integer
      add :steps, :text, null: false, default: "[]"
      add :tags, :string

      timestamps(type: :utc_datetime)
    end

    create index(:workouts, [:user_id])
  end
end
