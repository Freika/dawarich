defmodule DawarichWeb.Api.StandaloneMap do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.Repo
  alias DawarichWeb.StandaloneError

  def enabled?(_conn, _params), do: Dawarich.Standalone.enabled?()
  def init(action), do: action

  def call(conn, :settings), do: DawarichWeb.Api.SettingsController.call(conn, :index)

  def call(conn, :progress) do
    conn = DawarichWeb.Api.Auth.admit(conn, conn.assigns.api_user, [])
    if conn.halted, do: conn, else: handle(conn, :progress)
  end

  def call(conn, action), do: handle(conn, action)

  defp handle(conn, action) do
    if Dawarich.ReleaseMigration.self_hosted?() do
      case Dawarich.RailsTime.with_zone(conn.assigns.api_user.timezone, fn ->
             run(conn, action, Map.merge(conn.assigns.api_params, conn.path_params))
           end) do
        %Plug.Conn{} = result -> result
        _ -> StandaloneError.respond(conn, "standalone_map_timezone", 422)
      end
    else
      StandaloneError.respond(conn, "standalone_map_cloud")
    end
  rescue
    _ -> StandaloneError.respond(conn, "standalone_map_failure", 500)
  end

  defp run(conn, :progress, _params) do
    key = "transportation_mode_recalculation:user:#{conn.assigns.api_user.id}"

    case Dawarich.RailsCache.get(key) do
      :miss -> json(conn, 200, %{status: "idle"})
      {:ok, value} when is_map(value) -> json(conn, 200, value)
      _ -> StandaloneError.respond(conn, "standalone_map_progress", 500)
    end
  end

  defp run(conn, :bounds, params) do
    with {:ok, {from, to}} <- range(params["start_date"], params["end_date"]),
         {:ok, import_id} <- optional_id(params["import_id"]) do
      [[count, min_lat, max_lat, min_lng, max_lng]] =
        Repo.query!(
          """
          SELECT count(*), ST_YMin(ST_Extent(lonlat::geometry)), ST_YMax(ST_Extent(lonlat::geometry)),
            ST_XMin(ST_Extent(lonlat::geometry)), ST_XMax(ST_Extent(lonlat::geometry))
          FROM points WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3
            AND (anomaly = false OR anomaly IS NULL) AND ($4::bigint IS NULL OR import_id = $4)
          """,
          [conn.assigns.api_user.id, from, to, import_id],
          log: false
        ).rows

      if count == 0,
        do:
          json(conn, 404, %{error: "No data found for the specified date range", point_count: 0}),
        else:
          json(conn, 200, %{
            point_count: count,
            min_lat: min_lat,
            max_lat: max_lat,
            min_lng: min_lng,
            max_lng: max_lng
          })
    else
      _ -> StandaloneError.respond(conn, "standalone_map_bounds", 422)
    end
  end

  defp run(conn, kind, params) when kind in [:points, :tracks] do
    with false <- params["speed_coloring"] == "true",
         {:ok, {z, x, y}} <- coordinates(params),
         {:ok, {from, to}} <- range(params["start_at"], params["end_at"]),
         {:ok, import_id} <- optional_id(params["import_id"]) do
      {:ok, tile} =
        Repo.transaction(fn ->
          Repo.query!("SET LOCAL statement_timeout = '5s'", [], log: false)

          [[tile]] =
            Repo.query!(
              Dawarich.MapTiles.sql(kind),
              [conn.assigns.api_user.id, from, to, import_id, z, x, y],
              log: false
            ).rows

          tile
        end)

      conn =
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("vary", "Authorization")

      if tile == "",
        do: conn |> send_resp(204, "") |> halt(),
        else:
          conn
          |> put_resp_header("content-type", "application/vnd.mapbox-vector-tile")
          |> send_resp(200, tile)
          |> halt()
    else
      true -> StandaloneError.respond(conn, "standalone_map_speed_coloring", 422)
      :invalid_coordinates -> json(conn, 400, %{error: "Invalid tile coordinates"})
      _ -> StandaloneError.respond(conn, "standalone_map_range", 422)
    end
  end

  defp coordinates(params) do
    with {z, ""} <- Integer.parse(params["z"]),
         {x, ""} <- Integer.parse(params["x"]),
         {y, ""} <- Integer.parse(String.replace_suffix(params["y"], ".mvt", "")),
         true <-
           z in 0..22 and x >= 0 and y >= 0 and x < Integer.pow(2, z) and y < Integer.pow(2, z),
         do: {:ok, {z, x, y}},
         else: (_ -> :invalid_coordinates)
  end

  defp range(nil, nil), do: {:ok, {0, 4_102_444_800}}
  defp range(nil, _), do: :error
  defp range(_, nil), do: :error
  defp range(from, to), do: Dawarich.MapApi.Params.safe_range(from, to, DateTime.utc_now())
  defp optional_id(nil), do: {:ok, nil}

  defp optional_id(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end

  defp json(conn, status, term),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(term))
      |> halt()
end
