defmodule DawarichWeb.Api.TrackTilesController do
  @moduledoc false
  @behaviour Plug
  def init(action), do: action

  def call(conn, :show),
    do:
      Dawarich.Tiles.Http.call(conn, "tracks", Dawarich.Tiles.Tracks, [
        6,
        conn.assigns.api_params["speed_coloring"] == "true"
      ])
end
