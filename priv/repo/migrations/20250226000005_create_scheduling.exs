defmodule GarminPlanner.Repo.Migrations.CreateScheduling do
  use Ecto.Migration

  def change do
    create table(:garmin_workout_pushes) do
      add :workout_id, references(:workouts, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :garmin_workout_id, :integer, null: false
      add :pushed_at, :utc_datetime
      add :last_synced_at, :utc_datetime
    end

    create index(:garmin_workout_pushes, [:workout_id, :user_id])

    create table(:scheduled_plans) do
      add :plan_id, references(:training_plans, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :start_date, :date, null: false
      add :status, :string, null: false, default: "draft"

      timestamps(type: :utc_datetime)
    end

    create index(:scheduled_plans, [:plan_id, :user_id])

    create table(:scheduled_workouts) do
      add :scheduled_plan_id, references(:scheduled_plans, on_delete: :delete_all), null: false
      add :plan_workout_id, references(:plan_workouts, on_delete: :restrict), null: false
      add :scheduled_date, :date, null: false
      add :workout_id, references(:workouts, on_delete: :nilify_all)
      add :garmin_workout_id, :integer
      add :garmin_schedule_id, :integer
      add :push_status, :string, null: false, default: "pending"
      add :push_error, :text
      add :pushed_at, :utc_datetime
    end

    create index(:scheduled_workouts, [:scheduled_plan_id])
    create index(:scheduled_workouts, [:scheduled_date])
  end
end
