defmodule GarminPlanner.AccountsTest do
  use GarminPlanner.DataCase, async: true

  alias GarminPlanner.Accounts
  alias GarminPlanner.Accounts.User
  alias GarminPlanner.PaceZones

  describe "create_user/1" do
    test "creates a user with valid attrs" do
      assert {:ok, user} = Accounts.create_user(%{name: "Alice", unit_preference: "miles"})
      assert user.name == "Alice"
      assert user.unit_preference == "miles"
    end

    test "seeds default pace zones on creation" do
      {:ok, user} = Accounts.create_user(%{name: "Bob", unit_preference: "km"})
      zones = PaceZones.list_zones_for_user(user)
      assert length(zones) == 6
      zone_names = Enum.map(zones, & &1.name)
      assert "easy" in zone_names
      assert "threshold" in zone_names
    end

    test "requires name" do
      assert {:error, changeset} = Accounts.create_user(%{unit_preference: "miles"})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "validates unit_preference" do
      assert {:error, changeset} =
               Accounts.create_user(%{name: "Alice", unit_preference: "furlongs"})

      assert errors_on(changeset).unit_preference != []
    end

    test "sets default unit_preference to miles" do
      {:ok, user} = Accounts.create_user(%{name: "Charlie", unit_preference: "miles"})
      assert user.unit_preference == "miles"
    end
  end

  describe "update_user/2" do
    setup do
      {:ok, user} = Accounts.create_user(%{name: "Alice", unit_preference: "miles"})
      {:ok, user: user}
    end

    test "updates with valid attrs", %{user: user} do
      assert {:ok, updated} = Accounts.update_user(user, %{name: "Alicia", unit_preference: "km"})
      assert updated.name == "Alicia"
      assert updated.unit_preference == "km"
    end

    test "rejects invalid unit", %{user: user} do
      assert {:error, changeset} = Accounts.update_user(user, %{unit_preference: "invalid"})
      assert errors_on(changeset).unit_preference != []
    end
  end

  describe "delete_user/1" do
    test "deletes the user" do
      {:ok, user} = Accounts.create_user(%{name: "Temp", unit_preference: "miles"})
      assert {:ok, _} = Accounts.delete_user(user)
      assert Accounts.get_user(user.id) == nil
    end
  end

  describe "User.garmin_connected?/1" do
    test "returns false when not connected" do
      user = %User{garmin_connected_at: nil}
      refute User.garmin_connected?(user)
    end

    test "returns true when connected_at is set" do
      user = %User{garmin_connected_at: DateTime.utc_now()}
      assert User.garmin_connected?(user)
    end
  end

  describe "connect_garmin/2 and disconnect_garmin/1" do
    test "stores and clears connection" do
      {:ok, user} = Accounts.create_user(%{name: "Runner", unit_preference: "miles"})
      refute User.garmin_connected?(user)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, connected} =
        Accounts.connect_garmin(user, %{
          garmin_username: "runner@garmin",
          garmin_oauth1_token: "tok1",
          garmin_oauth1_secret: "sec1",
          garmin_oauth1_expires_at: now,
          garmin_oauth2_access_token: "access",
          garmin_oauth2_refresh_token: "refresh",
          garmin_oauth2_expires_at: now,
          garmin_oauth2_refresh_expires_at: now,
          garmin_connected_at: now
        })

      assert User.garmin_connected?(connected)

      {:ok, disconnected} = Accounts.disconnect_garmin(connected)
      refute User.garmin_connected?(disconnected)
    end
  end
end
