defmodule GarminPlanner.PaceZones.PaceZone do
  use Ecto.Schema
  import Ecto.Changeset

  alias GarminPlanner.Accounts.User

  @default_zones [
    %{name: "easy", label: "Easy / Recovery", color_hex: "#3B82F6", sort_order: 1},
    %{name: "moderate", label: "Moderate / GA", color_hex: "#10B981", sort_order: 2},
    %{name: "tempo", label: "Tempo / Comfortably Hard", color_hex: "#F59E0B", sort_order: 3},
    %{name: "threshold", label: "Threshold / LT", color_hex: "#EF4444", sort_order: 4},
    %{name: "5k_pace", label: "5K Race Pace", color_hex: "#8B5CF6", sort_order: 5},
    %{name: "interval", label: "VO₂max Intervals", color_hex: "#EC4899", sort_order: 6}
  ]

  schema "pace_zones" do
    belongs_to :user, User
    field :name, :string
    field :label, :string
    field :min_pace_ms, :integer
    field :max_pace_ms, :integer
    field :color_hex, :string
    field :sort_order, :integer

    timestamps(type: :utc_datetime)
  end

  def changeset(pace_zone, attrs) do
    pace_zone
    |> cast(attrs, [:name, :label, :min_pace_ms, :max_pace_ms, :color_hex, :sort_order, :user_id])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, max: 64)
    |> validate_pace_order()
    |> unique_constraint([:user_id, :name])
  end

  defp validate_pace_order(changeset) do
    min = get_field(changeset, :min_pace_ms)
    max = get_field(changeset, :max_pace_ms)

    if min && max && min >= max do
      add_error(changeset, :min_pace_ms, "must be faster (lower ms/m) than max pace")
    else
      changeset
    end
  end

  @doc """
  Convert milliseconds-per-meter to a human-readable pace string.
  Unit is :miles or :km.
  """
  def pace_ms_to_string(nil, _unit), do: nil

  def pace_ms_to_string(pace_ms, :miles) do
    total_seconds = round(pace_ms * 1609.34 / 1000)
    format_pace(total_seconds)
  end

  def pace_ms_to_string(pace_ms, :km) do
    total_seconds = round(pace_ms * 1.0)
    format_pace(total_seconds)
  end

  @doc """
  Convert a pace string like "8:30" and unit to ms/m.
  """
  def pace_string_to_ms(pace_str, :miles) do
    case parse_pace(pace_str) do
      {:ok, seconds} -> {:ok, round(seconds * 1000 / 1609.34)}
      err -> err
    end
  end

  def pace_string_to_ms(pace_str, :km) do
    case parse_pace(pace_str) do
      {:ok, seconds} -> {:ok, seconds * 1}
      err -> err
    end
  end

  @doc "Returns the Garmin speed (m/s) for the slow end of the zone."
  def garmin_min_speed(%__MODULE__{max_pace_ms: nil}), do: nil
  def garmin_min_speed(%__MODULE__{max_pace_ms: ms}), do: 1000.0 / ms

  @doc "Returns the Garmin speed (m/s) for the fast end of the zone."
  def garmin_max_speed(%__MODULE__{min_pace_ms: nil}), do: nil
  def garmin_max_speed(%__MODULE__{min_pace_ms: ms}), do: 1000.0 / ms

  def default_zones, do: @default_zones

  defp format_pace(total_seconds) do
    minutes = div(total_seconds, 60)
    seconds = rem(total_seconds, 60)
    "#{minutes}:#{String.pad_leading(to_string(seconds), 2, "0")}"
  end

  defp parse_pace(pace_str) do
    case String.split(pace_str, ":") do
      [min_str, sec_str] ->
        with {minutes, ""} <- Integer.parse(min_str),
             {seconds, ""} <- Integer.parse(sec_str),
             true <- seconds >= 0 and seconds < 60 do
          {:ok, minutes * 60 + seconds}
        else
          _ -> {:error, "invalid pace format, expected M:SS"}
        end

      _ ->
        {:error, "invalid pace format, expected M:SS"}
    end
  end
end
