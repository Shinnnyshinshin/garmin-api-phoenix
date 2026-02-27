defmodule GarminPlanner.Workouts.YAMLParserTest do
  use ExUnit.Case, async: true

  alias GarminPlanner.Workouts.YAMLParser

  describe "parse/1 — basic structure" do
    test "parses a minimal workout" do
      yaml = """
      name: "Easy Run"
      steps:
        - type: interval
          duration: 30min
          target: easy
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      assert attrs.name == "Easy Run"
      steps = Jason.decode!(attrs.steps)
      assert length(steps) == 1
      assert hd(steps)["type"] == "interval"
    end

    test "parses name, description, tags" do
      yaml = """
      name: "Threshold Intervals"
      description: "Classic LT work"
      tags: ["threshold", "tuesday"]
      steps:
        - type: interval
          duration: 20min
          target: threshold
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      assert attrs.name == "Threshold Intervals"
      assert attrs.description == "Classic LT work"
      assert attrs.tags =~ "threshold"
      assert attrs.tags =~ "tuesday"
    end

    test "returns error for non-mapping input" do
      assert {:error, _} = YAMLParser.parse("- item1\n- item2")
    end
  end

  describe "parse/1 — duration parsing" do
    test "parses minutes shorthand" do
      yaml = """
      name: "Test"
      steps:
        - type: warmup
          duration: 10min
          target: easy
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["duration_type"] == "time"
      assert step["duration_value"] == 600
      assert step["duration_unit"] == "seconds"
    end

    test "parses seconds shorthand" do
      yaml = """
      name: "Test"
      steps:
        - type: recovery
          duration: 90sec
          target: easy
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["duration_value"] == 90
    end

    test "parses distance in miles" do
      yaml = """
      name: "Test"
      steps:
        - type: interval
          distance: 1mi
          target: threshold
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["duration_type"] == "distance"
      assert step["duration_value"] == 1.0
      assert step["duration_unit"] == "miles"
    end

    test "parses distance in meters" do
      yaml = """
      name: "Test"
      steps:
        - type: interval
          distance: 800m
          target: interval
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["duration_value"] == 800.0
      assert step["duration_unit"] == "meters"
    end

    test "parses distance in km" do
      yaml = """
      name: "Test"
      steps:
        - type: interval
          distance: 5km
          target: easy
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["duration_value"] == 5.0
      assert step["duration_unit"] == "km"
    end

    test "step with no duration defaults to open" do
      yaml = """
      name: "Test"
      steps:
        - type: rest
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["duration_type"] == "open"
    end
  end

  describe "parse/1 — target parsing" do
    test "named zone target" do
      yaml = """
      name: "Test"
      steps:
        - type: interval
          duration: 20min
          target: tempo
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["target"]["type"] == "zone"
      assert step["target"]["zone_name"] == "tempo"
    end

    test "no target defaults to none" do
      yaml = """
      name: "Test"
      steps:
        - type: rest
          duration: 90sec
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["target"]["type"] == "none"
    end

    test "open target" do
      yaml = """
      name: "Test"
      steps:
        - type: interval
          duration: 10min
          target: open
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["target"]["type"] == "none"
    end

    test "explicit pace range with miles" do
      yaml = """
      name: "Test"
      steps:
        - type: interval
          duration: 20min
          target: "6:50-7:05/mi"
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["target"]["type"] == "pace_range"
      assert step["target"]["min_pace"] == "6:50/mi"
      assert step["target"]["max_pace"] == "7:05/mi"
    end

    test "explicit pace range with km" do
      yaml = """
      name: "Test"
      steps:
        - type: interval
          duration: 20min
          target: "4:15-4:30/km"
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [step] = Jason.decode!(attrs.steps)
      assert step["target"]["type"] == "pace_range"
      assert step["target"]["min_pace"] == "4:15/km"
      assert step["target"]["max_pace"] == "4:30/km"
    end
  end

  describe "parse/1 — repeat groups" do
    test "parses a repeat group with nested steps" do
      yaml = """
      name: "Threshold Intervals"
      steps:
        - type: warmup
          duration: 10min
          target: easy
        - type: repeat
          iterations: 5
          steps:
            - type: interval
              distance: 1mi
              target: threshold
            - type: recovery
              duration: 90sec
              target: easy
        - type: cooldown
          duration: 10min
          target: easy
      """

      assert {:ok, attrs} = YAMLParser.parse(yaml)
      [warmup, repeat, cooldown] = Jason.decode!(attrs.steps)

      assert warmup["type"] == "warmup"
      assert repeat["type"] == "repeat"
      assert repeat["iterations"] == 5
      assert length(repeat["steps"]) == 2
      assert cooldown["type"] == "cooldown"

      [interval, recovery] = repeat["steps"]
      assert interval["type"] == "interval"
      assert interval["duration_unit"] == "miles"
      assert recovery["type"] == "recovery"
      assert recovery["duration_value"] == 90
    end

    test "errors when repeat missing iterations" do
      yaml = """
      name: "Test"
      steps:
        - type: repeat
          steps:
            - type: interval
              duration: 5min
              target: easy
      """

      assert {:error, reason} = YAMLParser.parse(yaml)
      assert reason =~ "iterations"
    end
  end

  describe "parse/1 — step type validation" do
    test "errors on unknown step type" do
      yaml = """
      name: "Test"
      steps:
        - type: sprinting
          duration: 5min
      """

      assert {:error, reason} = YAMLParser.parse(yaml)
      assert reason =~ "unknown step type"
    end

    test "errors when step missing type" do
      yaml = """
      name: "Test"
      steps:
        - duration: 5min
          target: easy
      """

      assert {:error, reason} = YAMLParser.parse(yaml)
      assert reason =~ "missing 'type'"
    end
  end

  describe "steps_to_yaml/1" do
    test "round-trips a simple step list" do
      steps = [
        %{
          "type" => "warmup",
          "duration_type" => "time",
          "duration_value" => 600,
          "duration_unit" => "seconds",
          "target" => %{"type" => "zone", "zone_name" => "easy"}
        },
        %{
          "type" => "interval",
          "duration_type" => "time",
          "duration_value" => 1200,
          "duration_unit" => "seconds",
          "target" => %{"type" => "zone", "zone_name" => "tempo"}
        }
      ]

      yaml = YAMLParser.steps_to_yaml(steps)
      assert yaml =~ "type: warmup"
      assert yaml =~ "duration: 10min"
      assert yaml =~ "target: easy"
      assert yaml =~ "type: interval"
      assert yaml =~ "target: tempo"
    end
  end
end
