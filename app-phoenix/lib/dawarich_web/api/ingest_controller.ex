defmodule DawarichWeb.Api.IngestController do
  @moduledoc false
  @behaviour Plug

  require Logger

  alias Dawarich.I18n
  alias Dawarich.Ingest.{Friends, GeoJSON, Intake, OwnTracks, Timestamp, Traccar}
  alias DawarichWeb.Api.{Body, Respond}

  @failed %{
    points: "controllers.api.v1.points.point_creation_failed",
    overland: "controllers.api.v1.overland.batches.batch_creation_failed",
    owntracks: "controllers.api.v1.owntracks.points.point_creation_failed",
    traccar: "controllers.api.v1.traccar.points.point_creation_failed"
  }

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action),
    do: run(action, conn, conn.assigns.api_params, conn.assigns.api_user.id)

  defp run(:points, conn, params, user) do
    with {:ok, prepared} <-
           prepare(conn, fn -> params |> GeoJSON.points(user) |> Intake.prepare(user) end),
         {:ok, rows} <- write(conn, :points, prepared, user),
         do: Respond.json(conn, 200, {:object, [{"data", Enum.map(rows, &row/1)}]})
  end

  defp run(:overland, conn, params, user) do
    with {:ok, prepared} <-
           prepare(conn, fn -> params |> GeoJSON.overland() |> Intake.prepare(user) end),
         {:ok, _rows} <- write(conn, :overland, prepared, user),
         do: Respond.json(conn, 201, {:object, [{"result", "ok"}]})
  end

  defp run(:owntracks, conn, params, user) do
    with {:ok, {prepared, friends}} <-
           prepare(conn, fn ->
             {params |> OwnTracks.payloads() |> Intake.prepare(user), Friends.for_user(user)}
           end),
         {:ok, _rows} <- write(conn, :owntracks, prepared, user),
         do: Respond.json(conn, 200, friends)
  end

  defp run(:traccar, conn, params, user) do
    case prepare(conn, fn -> params |> Traccar.payloads() |> Intake.prepare(user) end) do
      {:ok, []} ->
        Respond.json(conn, 422, {:object, [{"error", t(@failed.traccar)}]})

      {:ok, prepared} ->
        with {:ok, _rows} <- write(conn, :traccar, prepared, user),
             do: Respond.json(conn, 200, [])

      replayed ->
        replayed
    end
  end

  defp prepare(conn, fun) do
    {:ok, fun.()}
  rescue
    error in Timestamp.Invalid -> Respond.json(conn, 422, {:object, [{"error", error.message}]})
    error -> Body.replay(conn, Exception.message(error))
  end

  defp write(conn, action, prepared, user) do
    {:ok, Intake.write(prepared, user)}
  rescue
    error ->
      Logger.error("[ingest] #{conn.request_path} write failed: #{inspect(error.__struct__)}")
      Respond.json(conn, 500, {:object, [{"error", t(@failed[action])}]})
  end

  defp row(row),
    do:
      {:object,
       [
         {"id", row.id},
         {"timestamp", row.timestamp},
         {"longitude", row.longitude},
         {"latitude", row.latitude}
       ]}

  defp t(key) do
    {:ok, value} = I18n.t("en", key)
    value
  end
end
