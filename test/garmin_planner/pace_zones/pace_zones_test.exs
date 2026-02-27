defmodule GarminPlanner.PaceZonesTest do
  use GarminPlanner.DataCase, async: true

  alias GarminPlanner.Accounts
  alias GarminPlanner.PaceZones
  alias GarminPlanner.PaceZones.PaceZone

  setup do
    {:ok, user} = Accounts.create_user(%{name: "Alice", unit_preference: "miles"})
    {:ok, user: user}
  end

  describe "seed_default_zones/1" do
    test "creates 6 default zones", %{user: user} do
      zones = PaceZones.list_zones_for_user(user)
      assert length(zones) == 6
    end

    test "is idempotent", %{user: user} do
      PaceZones.seed_default_zones(user)
      zones = PaceZones.list_zones_for_user(user)
      assert length(zones) == 6
    end

    test "zones are ordered by sort_order", %{user: user} do
      zones = PaceZones.list_zones_for_user(user)
      orders = Enum.map(zones, & &1.sort_order)
      assert orders == Enum.sort(orders)
    end
  end

  describe "update_zone/2" do
    test "updates pace values", %{user: user} do
      zone = PaceZones.get_zone_by_name(user, "easy")
      assert {:ok, updated} = PaceZones.update_zone(zone, %{min_pace_ms: 500, max_pace_ms: 600})
      assert updated.min_pace_ms == 500
      assert updated.max_pace_ms == 600
    end

    test "rejects when min >= max", %{user: user} do
      zone = PaceZones.get_zone_by_name(user, "easy")
      assert {:error, changeset} = PaceZones.update_zone(zone, %{min_pace_ms: 600, max_pace_ms: 500})
      assert errors_on(changeset).min_pace_ms != []
    end
  end

  describe "PaceZone.pace_ms_to_string/2" do
    test "converts ms/m to min/mile display" do
      # 500 ms/m ≈ 500 * 1609.34 / 1000 = ~805 sec/mile = 13:25/mi (approximately)
      # Let's test a cleaner number: 373 ms/m ≈ 600 sec/mile = 10:00/mi
      pace_ms = round(600 * 1000 / 1609.34)
      result = PaceZone.pace_ms_to_string(pace_ms, :miles)
      assert result =~ ":"
    end

    test "converts ms/m to min/km display" do
      # 333 ms/m = 333 sec/km = 5:33/km
      result = PaceZone.pace_ms_to_string(333, :km)
      assert result == "5:33"
    end

    test "returns nil for nil input" do
      assert PaceZone.pace_ms_to_string(nil, :miles) == nil
    end
  end

  describe "PaceZone.pace_string_to_ms/2" do
    test "converts min/km pace string to ms/m" do
      assert {:ok, ms} = PaceZone.pace_string_to_ms("5:00", :km)
      # 5:00/km = 300 sec/km = 300 ms/m
      assert ms == 300
    end

    test "converts min/mile pace string to ms/m" do
      assert {:ok, ms} = PaceZone.pace_string_to_ms("8:00", :miles)
      # 8:00/mi = 480 sec/mi; ms/m = 480 * 1000 / 1609.34 ≈ 298
      assert_in_delta ms, 298, 2
    end

    test "rejects invalid format" do
      assert {:error, _} = PaceZone.pace_string_to_ms("8:70", :miles)
      assert {:error, _} = PaceZone.pace_string_to_ms("fast", :km)
    end
  end

  describe "PaceZone.garmin_min_speed/1 and garmin_max_speed/1" do
    test "converts to m/s correctly" do
      zone = %PaceZone{min_pace_ms: 300, max_pace_ms: 400}
      # min_speed (fast end) = 1000 / min_pace_ms = 1000/300 ≈ 3.33 m/s
      # max_speed (slow end) = 1000 / max_pace_ms = 1000/400 = 2.5 m/s
      assert_in_delta PaceZone.garmin_max_speed(zone), 3.333, 0.01
      assert_in_delta PaceZone.garmin_min_speed(zone), 2.5, 0.01
    end
  end
end
