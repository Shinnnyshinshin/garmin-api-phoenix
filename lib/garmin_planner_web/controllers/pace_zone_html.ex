defmodule GarminPlannerWeb.PaceZoneHTML do
  use GarminPlannerWeb, :html

  alias GarminPlanner.PaceZones.PaceZone

  embed_templates "pace_zone_html/*"

  def pace_display(nil, _unit), do: ""

  def pace_display(pace_ms, unit_str) do
    unit = String.to_existing_atom(unit_str)
    PaceZone.pace_ms_to_string(pace_ms, unit) || ""
  end
end
