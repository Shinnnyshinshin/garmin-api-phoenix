defmodule GarminPlanner.Workouts.YAMLParser do
  @moduledoc """
  Parses the YAML workout format into the internal step JSON schema.

  Returns {:ok, %{name: _, description: _, tags: _, steps: _}} or {:error, reason}.
  """

  @valid_step_types ~w(warmup cooldown interval recovery rest repeat)

  @doc """
  Parse a YAML string into a workout map with decoded steps.

  Returns `{:ok, workout_attrs}` or `{:error, reason}`.
  """
  def parse(yaml_string) when is_binary(yaml_string) do
    with {:ok, raw} <- YamlElixir.read_from_string(yaml_string),
         :ok <- validate_map(raw, "workout"),
         {:ok, steps} <- parse_steps(Map.get(raw, "steps", [])) do
      attrs = %{
        name: Map.get(raw, "name", ""),
        description: Map.get(raw, "description"),
        tags: parse_tags(Map.get(raw, "tags")),
        steps: Jason.encode!(steps)
      }

      {:ok, attrs}
    end
  end

  defp validate_map(val, _ctx) when is_map(val), do: :ok
  defp validate_map(_, ctx), do: {:error, "#{ctx} must be a YAML mapping"}

  defp parse_tags(nil), do: nil
  defp parse_tags(tags) when is_list(tags), do: Enum.join(tags, ", ")
  defp parse_tags(tags) when is_binary(tags), do: tags

  defp parse_steps(nil), do: {:ok, []}
  defp parse_steps([]), do: {:ok, []}

  defp parse_steps(steps) when is_list(steps) do
    steps
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {raw_step, idx}, {:ok, acc} ->
      case parse_step(raw_step, "step #{idx}") do
        {:ok, step} -> {:cont, {:ok, acc ++ [step]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp parse_steps(_), do: {:error, "steps must be a list"}

  defp parse_step(%{"type" => "repeat"} = raw, ctx) do
    with :ok <- validate_step_type("repeat", ctx),
         iterations when is_integer(iterations) <- Map.get(raw, "iterations"),
         {:ok, inner_steps} <- parse_steps(Map.get(raw, "steps", [])) do
      {:ok,
       %{
         "type" => "repeat",
         "iterations" => iterations,
         "steps" => inner_steps
       }}
    else
      nil -> {:error, "#{ctx}: repeat step requires 'iterations'"}
      false -> {:error, "#{ctx}: 'iterations' must be an integer"}
      err -> err
    end
  end

  defp parse_step(%{"type" => type} = raw, ctx) do
    with :ok <- validate_step_type(type, ctx),
         {:ok, duration_type, duration_value, duration_unit} <- parse_duration(raw, ctx),
         {:ok, target} <- parse_target(raw, ctx) do
      {:ok,
       %{
         "type" => type,
         "duration_type" => duration_type,
         "duration_value" => duration_value,
         "duration_unit" => duration_unit,
         "target" => target
       }}
    end
  end

  defp parse_step(%{}, ctx), do: {:error, "#{ctx}: missing 'type' field"}
  defp parse_step(_, ctx), do: {:error, "#{ctx}: step must be a mapping"}

  defp validate_step_type(type, ctx) do
    if type in @valid_step_types do
      :ok
    else
      {:error, "#{ctx}: unknown step type '#{type}', must be one of #{Enum.join(@valid_step_types, ", ")}"}
    end
  end

  # Duration parsing: "10min", "90sec", "1mi", "800m", "5km"
  defp parse_duration(raw, _ctx) do
    cond do
      Map.has_key?(raw, "duration") ->
        case parse_duration_string(raw["duration"]) do
          {:ok, value, unit} -> {:ok, "time", value, unit}
          {:error, _} = err -> err
        end

      Map.has_key?(raw, "distance") ->
        case parse_distance_string(raw["distance"]) do
          {:ok, value, unit} -> {:ok, "distance", value, unit}
          {:error, _} = err -> err
        end

      raw["type"] == "rest" ->
        {:ok, "open", nil, nil}

      true ->
        {:ok, "open", nil, nil}
    end
  end

  defp parse_duration_string(val) when is_binary(val) do
    cond do
      String.ends_with?(val, "min") ->
        {n, ""} = Integer.parse(String.replace_suffix(val, "min", ""))
        {:ok, n * 60, "seconds"}

      String.ends_with?(val, "sec") ->
        {n, ""} = Integer.parse(String.replace_suffix(val, "sec", ""))
        {:ok, n, "seconds"}

      true ->
        {:error, "invalid duration '#{val}', use '10min' or '90sec'"}
    end
  end

  defp parse_duration_string(val) when is_integer(val), do: {:ok, val, "seconds"}
  defp parse_duration_string(val), do: {:error, "duration must be a string like '10min', got: #{inspect(val)}"}

  defp parse_distance_string(val) when is_binary(val) do
    cond do
      String.ends_with?(val, "mi") ->
        {n, ""} = Float.parse(String.replace_suffix(val, "mi", ""))
        {:ok, n, "miles"}

      String.ends_with?(val, "km") ->
        {n, ""} = Float.parse(String.replace_suffix(val, "km", ""))
        {:ok, n, "km"}

      String.ends_with?(val, "m") ->
        {n, ""} = Float.parse(String.replace_suffix(val, "m", ""))
        {:ok, n, "meters"}

      true ->
        {:error, "invalid distance '#{val}', use '1mi', '800m', or '5km'"}
    end
  end

  defp parse_distance_string(val) when is_number(val), do: {:ok, val * 1.0, "meters"}
  defp parse_distance_string(val), do: {:error, "distance must be a string like '1mi', got: #{inspect(val)}"}

  # Target parsing
  defp parse_target(raw, _ctx) do
    case Map.get(raw, "target") do
      nil ->
        {:ok, %{"type" => "none"}}

      "open" ->
        {:ok, %{"type" => "none"}}

      zone_name when is_binary(zone_name) ->
        case parse_explicit_pace(zone_name) do
          {:ok, target} -> {:ok, target}
          :not_pace -> {:ok, %{"type" => "zone", "zone_name" => zone_name}}
        end

      _ ->
        {:ok, %{"type" => "none"}}
    end
  end

  # Try to parse an explicit pace range like "6:50-7:05/mi" or "4:15-4:25/km"
  defp parse_explicit_pace(str) do
    cond do
      String.contains?(str, "/mi") ->
        case parse_pace_range(str, "/mi") do
          {:ok, min, max} -> {:ok, %{"type" => "pace_range", "min_pace" => "#{min}/mi", "max_pace" => "#{max}/mi"}}
          _ -> :not_pace
        end

      String.contains?(str, "/km") ->
        case parse_pace_range(str, "/km") do
          {:ok, min, max} -> {:ok, %{"type" => "pace_range", "min_pace" => "#{min}/km", "max_pace" => "#{max}/km"}}
          _ -> :not_pace
        end

      true ->
        :not_pace
    end
  end

  defp parse_pace_range(str, suffix) do
    str
    |> String.replace_suffix(suffix, "")
    |> String.split("-")
    |> case do
      [min, max] -> {:ok, String.trim(min), String.trim(max)}
      _ -> :error
    end
  end

  @doc """
  Convert a step tree back to YAML for display in the editor.
  """
  def steps_to_yaml(steps) when is_list(steps) do
    lines = ["steps:"] ++ Enum.flat_map(steps, &step_to_yaml_lines(&1, 2))
    Enum.join(lines, "\n")
  end

  defp step_to_yaml_lines(%{"type" => "repeat", "iterations" => n, "steps" => inner}, indent) do
    prefix = String.duplicate(" ", indent)
    inner_lines = Enum.flat_map(inner, &step_to_yaml_lines(&1, indent + 4))

    ["#{prefix}- type: repeat", "#{prefix}  iterations: #{n}", "#{prefix}  steps:"] ++
      inner_lines
  end

  defp step_to_yaml_lines(%{"type" => type} = step, indent) do
    prefix = String.duplicate(" ", indent)
    lines = ["#{prefix}- type: #{type}"]

    lines =
      case {step["duration_type"], step["duration_value"], step["duration_unit"]} do
        {"time", val, "seconds"} when is_integer(val) ->
          if rem(val, 60) == 0,
            do: lines ++ ["#{prefix}  duration: #{div(val, 60)}min"],
            else: lines ++ ["#{prefix}  duration: #{val}sec"]

        {"distance", val, unit} ->
          lines ++ ["#{prefix}  distance: #{format_distance(val, unit)}"]

        _ ->
          lines
      end

    case step["target"] do
      %{"type" => "zone", "zone_name" => name} ->
        lines ++ ["#{prefix}  target: #{name}"]

      %{"type" => "pace_range", "min_pace" => min, "max_pace" => max} ->
        # strip trailing /mi or /km to build range string
        unit = if String.ends_with?(min, "/mi"), do: "/mi", else: "/km"
        min_p = String.replace_suffix(min, unit, "")
        max_p = String.replace_suffix(max, unit, "")
        lines ++ ["#{prefix}  target: \"#{min_p}-#{max_p}#{unit}\""]

      _ ->
        lines
    end
  end

  defp format_distance(val, "miles"), do: "#{val}mi"
  defp format_distance(val, "km"), do: "#{val}km"
  defp format_distance(val, "meters"), do: "#{round(val)}m"
  defp format_distance(val, _), do: "#{val}"
end
