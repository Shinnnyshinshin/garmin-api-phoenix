defmodule GarminPlannerWeb.GarminAuthController do
  use GarminPlannerWeb, :controller

  alias GarminPlanner.Accounts

  @moduledoc """
  Handles the Garmin SSO auth flow for a user.

  NOTE: The actual OAuth exchange requires the nimrag fork (Phase 2).
  This controller wires the UI flow; the auth logic is stubbed until
  the nimrag fork is integrated.
  """

  def new(conn, %{"user_id" => user_id}) do
    user = Accounts.get_user!(user_id)
    render(conn, :new, user: user, error: nil)
  end

  def create(conn, %{"user_id" => _user_id, "garmin" => %{"username" => _username, "password" => _password}}) do

    # TODO: Replace stub with actual nimrag SSO flow once the fork is integrated.
    # The flow will be:
    #   1. GarminPlanner.Garmin.AuthFlow.authenticate(username, password)
    #   2. {:ok, tokens} -> Accounts.connect_garmin(user, tokens)
    #   3. {:mfa_required, state} -> render MFA form
    #   4. {:error, reason} -> render form with error

    conn
    |> put_flash(:warning, "Garmin auth integration pending (nimrag fork required). Tokens not stored.")
    |> redirect(to: ~p"/users")
  end

  def delete(conn, %{"user_id" => user_id}) do
    user = Accounts.get_user!(user_id)
    {:ok, _} = Accounts.disconnect_garmin(user)

    conn
    |> put_flash(:info, "Garmin account disconnected.")
    |> redirect(to: ~p"/users")
  end
end
