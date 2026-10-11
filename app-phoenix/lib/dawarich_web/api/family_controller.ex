defmodule DawarichWeb.Api.FamilyController do
  @moduledoc false
  @behaviour Plug

  alias DawarichWeb.Api.Respond

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)

    case run(action, conn.assigns.api_user, params, conn.assigns[:api_now] || DateTime.utc_now()) do
      {:ok, status, term} -> Respond.json(conn, status, term)
      {:replay, _reason} -> DawarichWeb.RailsErrors.respond(conn, 500, exception: true)
    end
  end

  def run(action, user, params, now) do
    Dawarich.FamilyApi.Closure.run(action, user, params, now)
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end
end
