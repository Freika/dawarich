defmodule DawarichWeb.Api.IngestController do
  @moduledoc false
  @behaviour Plug

  require Logger

  alias Dawarich.I18n

  alias Dawarich.Ingest.{
    Closure,
    Friends,
    GeoJSON,
    Intake,
    OwnTracks,
    Timestamp,
    Traccar,
    Unsupported
  }

  alias DawarichWeb.Api.{Body, Respond}

  @failed %{
    points: "controllers.api.v1.points.point_creation_failed",
    overland: "controllers.api.v1.overland.batches.batch_creation_failed",
    owntracks: "controllers.api.v1.owntracks.points.point_creation_failed",
    traccar: "controllers.api.v1.traccar.points.point_creation_failed"
  }

  @impl true
  def init({:native, action}),
    do: if(Dawarich.Standalone.enabled?(), do: {:native, action}, else: action)

  def init(action), do: action

  @impl true
  def call(conn, {:native, action}) do
    user = conn.assigns.api_user
    ctx = Dawarich.Imports.Api.context(conn)

    with :ok <- Dawarich.Imports.Api.guard(user, ctx, true, false),
         {:ok, prepared, _friends} <- Closure.prepare(action, conn.assigns.api_params, user.id) do
      if action == :traccar and prepared == [] do
        Respond.json(conn, 422, Closure.failed(action))
      else
        with {:ok, rows} <- write(conn, action, prepared, user.id) do
          {status, body} =
            case action do
              :points -> {200, {:object, [{"data", Enum.map(rows, &row/1)}]}}
              :overland -> {201, %{"result" => "ok"}}
              :owntracks -> {200, native_friends(user.id, ctx.now)}
              :traccar -> {200, []}
            end

          try do
            Map.get(ctx, :after_commit, fn -> :ok end).()
            Respond.json(conn, status, body)
          rescue
            _ -> Respond.json(conn, 500, Closure.failed(action))
          end
        end
      end
    else
      {:error, status, body} -> Respond.json(conn, status, body)
    end
  end

  def call(conn, action),
    do: run(action, conn, conn.assigns.api_params, conn.assigns.api_user.id)

  defp native_friends(user, now) do
    repo = Dawarich.Repo

    if repo.in_transaction?() do
      repo.query!("SAVEPOINT owntracks_friends")

      try do
        friends = Friends.for_user(user, now)
        repo.query!("RELEASE SAVEPOINT owntracks_friends")
        friends
      rescue
        _ ->
          repo.query!("ROLLBACK TO SAVEPOINT owntracks_friends")
          repo.query!("RELEASE SAVEPOINT owntracks_friends")
          []
      end
    else
      Friends.for_user(user, now)
    end
  rescue
    _ -> []
  end

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
        Respond.json(conn, 422, {:object, [{"error", I18n.en!(@failed.traccar)}]})

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
    error in Unsupported -> Body.replay(conn, error.reason)
    error -> Body.replay(conn, inspect(error.__struct__))
  end

  defp write(conn, action, prepared, user) do
    {:ok, Intake.write(prepared, user, conn.assigns[:ingest_write_opts] || [])}
  rescue
    error ->
      Logger.error(
        "[ingest] #{conn.request_path} write failed: #{inspect(error.__struct__)} sqlstate=#{sqlstate(error)} request_id=#{conn.assigns.api_request_id}"
      )

      Respond.json(conn, 500, {:object, [{"error", I18n.en!(@failed[action])}]})
  end

  defp sqlstate(%{postgres: %{code: code}}), do: code
  defp sqlstate(_error), do: "none"

  defp row(row),
    do:
      {:object,
       [
         {"id", row.id},
         {"timestamp", row.timestamp},
         {"longitude", row.longitude},
         {"latitude", row.latitude}
       ]}
end
