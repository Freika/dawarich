defmodule DawarichWeb.Api.PointPositionsController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Points.ApiPosition
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, :update) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)

    {_, status, body} =
      ApiPosition.update(
        Dawarich.Repo,
        conn.assigns.api_user,
        params["point_id"],
        params,
        Dawarich.Imports.Api.context(conn)
      )

    Respond.json(conn, status, body)
  rescue
    _ -> Respond.json(conn, 500, {:object, [{"status", 500}, {"error", "Internal Server Error"}]})
  end
end
