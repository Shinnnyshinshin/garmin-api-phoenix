defmodule GarminPlanner.Workouts.Workout do
  use Ecto.Schema
  import Ecto.Changeset

  alias GarminPlanner.Accounts.User

  @max_steps 50
  @sport_types ~w(running)

  schema "workouts" do
    belongs_to :user, User
    field :name, :string
    field :description, :string
    field :sport_type, :string, default: "running"
    field :estimated_duration_secs, :integer
    field :steps, :string, default: "[]"
    field :tags, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(workout, attrs) do
    workout
    |> cast(attrs, [:name, :description, :sport_type, :estimated_duration_secs, :steps, :tags, :user_id])
    |> validate_required([:name, :sport_type, :steps])
    |> validate_length(:name, max: 128)
    |> validate_inclusion(:sport_type, @sport_types)
    |> validate_steps()
  end

  defp validate_steps(changeset) do
    case get_field(changeset, :steps) do
      nil ->
        changeset

      steps_json ->
        case Jason.decode(steps_json) do
          {:ok, steps} when is_list(steps) ->
            total = count_steps(steps)

            changeset
            |> then(fn cs ->
              if total == 0, do: add_error(cs, :steps, "must have at least one step"), else: cs
            end)
            |> then(fn cs ->
              if total > @max_steps,
                do: add_error(cs, :steps, "exceeds Garmin limit of #{@max_steps} steps"),
                else: cs
            end)
            |> validate_step_structure(steps)

          _ ->
            add_error(changeset, :steps, "invalid JSON")
        end
    end
  end

  defp validate_step_structure(changeset, steps) do
    has_warmup = Enum.any?(steps, &(&1["type"] == "warmup"))
    has_cooldown = Enum.any?(steps, &(&1["type"] == "cooldown"))

    changeset
    |> then(fn cs ->
      if has_warmup && List.first(steps)["type"] != "warmup",
        do: add_error(cs, :steps, "warmup step must be first"),
        else: cs
    end)
    |> then(fn cs ->
      if has_cooldown && List.last(steps)["type"] != "cooldown",
        do: add_error(cs, :steps, "cooldown step must be last"),
        else: cs
    end)
    |> then(fn cs ->
      if has_nested_repeat?(steps),
        do: add_error(cs, :steps, "Garmin does not support nested repeat groups"),
        else: cs
    end)
  end

  defp count_steps(steps) do
    Enum.reduce(steps, 0, fn
      %{"type" => "repeat", "steps" => inner}, acc -> acc + 1 + length(inner)
      _, acc -> acc + 1
    end)
  end

  defp has_nested_repeat?(steps) do
    Enum.any?(steps, fn
      %{"type" => "repeat", "steps" => inner} ->
        Enum.any?(inner, &(&1["type"] == "repeat"))

      _ ->
        false
    end)
  end

  @doc "Returns a list of tag strings from the comma-separated tags field."
  def tag_list(%__MODULE__{tags: nil}), do: []

  def tag_list(%__MODULE__{tags: tags}) do
    tags |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  @doc "Decodes the steps JSON field, returning a list."
  def decoded_steps(%__MODULE__{steps: steps_json}) do
    case Jason.decode(steps_json) do
      {:ok, steps} -> steps
      _ -> []
    end
  end
end
