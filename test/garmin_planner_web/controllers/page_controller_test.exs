defmodule GarminPlannerWeb.PageControllerTest do
  use GarminPlannerWeb.ConnCase

  test "GET / renders home page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Garmin Workout Planner"
  end
end
