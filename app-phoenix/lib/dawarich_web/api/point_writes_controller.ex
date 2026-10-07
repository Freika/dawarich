defmodule DawarichWeb.Api.PointWritesController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Imports.Api
  alias Dawarich.Points.ApiWrites
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, action) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)
    user = conn.assigns.api_user
    ctx = Api.context(conn)

    result =
      case action do
        :update -> ApiWrites.update(Dawarich.Repo, user, params["id"], params, ctx)
        :destroy -> ApiWrites.destroy(Dawarich.Repo, user, params["id"], ctx)
        :bulk_destroy -> ApiWrites.bulk_destroy(Dawarich.Repo, user, params, ctx)
      end

    {_, status, body} = result

    body =
      if is_map(body) and Map.has_key?(body, "count"),
        do: {:object, [{"message", body["message"]}, {"count", body["count"]}]},
        else: body

    Respond.json(conn, status, body)
  rescue
    _ -> Respond.json(conn, 500, ApiWrites.failure())
  end
end
