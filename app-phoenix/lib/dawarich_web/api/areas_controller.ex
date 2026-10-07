defmodule DawarichWeb.Api.AreasController do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.Areas.Api
  alias DawarichWeb.Api.Respond
  def init(action), do: action

  def call(conn, action) do
    user = conn.assigns.api_user
    params = Map.merge(conn.assigns.api_params, conn.path_params)
    ctx = Dawarich.Settings.Api.context(conn)

    if action in [:create, :update] do
      DawarichWeb.Api.WriteResponse.call(conn, fn ->
        case action do
          :create -> Api.create(Dawarich.Repo, user, params, ctx)
          :update -> Api.update(Dawarich.Repo, user, params["id"], params, ctx)
        end
      end)
    else
      {_, status, body} =
        case action do
          :index -> Api.index(Dawarich.Repo, user, ctx)
          :show -> Api.show(Dawarich.Repo, user, params["id"], ctx)
          :destroy -> Api.destroy(Dawarich.Repo, user, params["id"], ctx)
        end

      Respond.json(conn, status, body)
    end
  rescue
    _ -> Respond.json(conn, 500, Dawarich.Settings.Api.failure())
  end
end
