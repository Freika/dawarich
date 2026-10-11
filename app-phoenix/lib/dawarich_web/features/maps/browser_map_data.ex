defmodule DawarichWeb.BrowserMapData do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.Api

  @paged [:points, :tracks, :track_points, :places, :visits, :photos, :areas]
  @handlers %{
    points: {Api.MapController, :points},
    tracks: {Api.MapController, :tracks},
    track: {Api.MapController, :track},
    track_points: {Api.MapController, :track_points},
    bounds: {Api.HexagonsController, :bounds},
    hexagons: {Api.HexagonsController, :index},
    fog: {Api.HexagonsController, :fog},
    flights: {Api.GeoController, :flights},
    countries: {Api.SpatialController, :visited},
    thumbnail: {Api.PhotosController, :thumbnail_closure},
    locations: {Api.LocationsController, :index_closure},
    suggestions: {Api.LocationsController, :suggestions},
    places: {Api.PlacesController, {:closure, :index}},
    place_search: {Api.PlacesController, :search},
    nearby: {Api.PlacesController, :nearby},
    visits: {Api.VisitsController, :index},
    timeline: {Api.TimelineController, :index},
    point_tiles: {Api.PointTilesController, :show},
    track_tiles: {Api.TrackTilesController, :show}
  }

  def init(action), do: action

  def call(conn, action) do
    with :ok <- readonly(conn), {:ok, params} <- bounded(conn.assigns.api_params, action) do
      conn = assign(conn, :api_params, params)

      case action do
        :trip ->
          trip(conn)

        family when family in [:family_locations, :family_history] ->
          family(conn, family)

        :areas ->
          DawarichWeb.BrowserMapAreas.call(conn)

        :photos ->
          DawarichWeb.BrowserMapPhotos.call(conn)

        :settings ->
          settings(conn)

        _ ->
          {module, operation} = Map.fetch!(@handlers, action)
          module.call(conn, operation)
      end
    else
      {:error, status} -> Api.Respond.json(conn, status, %{error: "invalid_read"})
    end
  rescue
    _ -> Api.Respond.json(conn, 500, %{error: "read_unavailable"})
  end

  defp readonly(%{method: method}) when method in ["GET", "HEAD"], do: :ok
  defp readonly(_), do: {:error, 405}

  defp bounded(params, action) when action in @paged do
    per = params["per_page"] || "1000"
    page = params["page"] || "1"

    with true <- is_binary(per) and is_binary(page),
         {per_n, ""} when per_n in 1..1000 <- Integer.parse(per),
         {page_n, ""} when page_n in 1..100_000 <- Integer.parse(page) do
      {:ok, params |> Map.put("per_page", per) |> Map.put("page", page)}
    else
      _ -> {:error, 422}
    end
  end

  defp bounded(params, _), do: {:ok, params}

  defp trip(conn) do
    user = Dawarich.Accounts.get(conn.assigns.api_user.id)
    scope = Dawarich.Maps.principal(user, "en")

    with {id, ""} <- Integer.parse(conn.path_params["id"]),
         {:ok, data} <-
           Dawarich.Maps.Trip.read(scope, id, now: conn.assigns[:now] || DateTime.utc_now()) do
      Api.Respond.json(conn, 200, data)
    else
      {:error, :stale_session} -> Api.Respond.json(conn, 401, %{error: "unauthorized"})
      _ -> Api.Respond.json(conn, 404, %{error: "not_found"})
    end
  end

  defp family(conn, action) do
    user = Dawarich.Accounts.get(conn.assigns.api_user.id)
    scope = Dawarich.Maps.principal(user, "en")
    operation = if action == :family_locations, do: :locations, else: :history

    case Dawarich.Maps.Family.read(scope, operation, conn.assigns.api_params,
           now: conn.assigns[:now] || DateTime.utc_now()
         ) do
      {:ok, status, body} -> Api.Respond.json(conn, status, body)
      {:error, _} -> Api.Respond.json(conn, 403, %{error: "family_unavailable"})
    end
  end

  defp settings(conn) do
    {_, status, body} =
      Dawarich.Settings.Api.index(
        Dawarich.Repo,
        conn.assigns.api_user,
        Dawarich.Settings.Api.context(conn)
      )

    body =
      if status == 200,
        do:
          Map.update!(
            body,
            "settings",
            &Map.drop(&1, ~w(immich_api_key photoprism_api_key airtrail_api_key))
          ),
        else: body

    Api.Respond.json(conn, status, Dawarich.Settings.Api.term(body))
  end
end
