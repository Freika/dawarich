defmodule DawarichWeb.Api.PointTilesController do
  @moduledoc false
  @behaviour Plug
  def init(action), do: action
  def call(conn, :show), do: Dawarich.Tiles.Http.call(conn, "points", Dawarich.Tiles.Points, 4)
end
