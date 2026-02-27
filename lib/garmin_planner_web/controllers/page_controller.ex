defmodule GarminPlannerWeb.PageController do
  use GarminPlannerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
