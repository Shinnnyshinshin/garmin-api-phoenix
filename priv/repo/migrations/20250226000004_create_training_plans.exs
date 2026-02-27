defmodule GarminPlanner.Repo.Migrations.CreateTrainingPlans do
  use Ecto.Migration

  def change do
    create table(:training_plans) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :total_weeks, :integer, null: false
      add :sport_type, :string, null: false, default: "running"

      timestamps(type: :utc_datetime)
    end

    create table(:plan_weeks) do
      add :plan_id, references(:training_plans, on_delete: :delete_all), null: false
      add :week_number, :integer, null: false
    end

    create unique_index(:plan_weeks, [:plan_id, :week_number])

    create table(:plan_workouts) do
      add :plan_week_id, references(:plan_weeks, on_delete: :delete_all), null: false
      add :day_of_week, :string, null: false
      add :workout_id, references(:workouts, on_delete: :nilify_all)
      add :inline_steps, :text
      add :workout_name, :string
      add :distance_override_value, :float
      add :distance_override_unit, :string
      add :notes, :text
    end

    create unique_index(:plan_workouts, [:plan_week_id, :day_of_week])
    create index(:plan_workouts, [:workout_id])
  end
end
