defmodule Dawarich.Metrics.Map do
  @moduledoc false
  import Telemetry.Metrics

  @move [:dawarich, :map, :move]
  @tile [:dawarich, :map, :tile]
  @duration [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3]

  def move(fun) do
    started = System.monotonic_time()

    try do
      {outcome, measurements, result} = fun.()

      if outcome do
        emit(@move, Map.merge(measurements, %{count: 1, duration: elapsed(started)}), %{
          outcome: outcome
        })
      end

      result
    rescue
      error in Postgrex.Error ->
        if error.postgres[:code] == :query_canceled do
          emit(@move, Map.merge(sizes(nil, nil), %{count: 1, duration: elapsed(started)}), %{
            outcome: "timeout"
          })
        end

        reraise error, __STACKTRACE__
    end
  end

  def sizes(repo, track, recalculated \\ false)
  def sizes(_repo, nil, _recalculated), do: %{lock_wait: 0, track_points: 1, track_segments: 0}

  def sizes(repo, track, recalculated) do
    [[segments]] =
      repo.query!("SELECT count(*) FROM track_segments WHERE track_id=$1", [track.id]).rows

    points =
      if recalculated do
        [[count]] =
          repo.query!("SELECT count(*) FROM points WHERE track_id=$1 AND anomaly IS NOT TRUE", [
            track.id
          ]).rows

        count
      else
        1
      end

    %{lock_wait: 0, track_points: points, track_segments: segments}
  end

  def post_commit_failure(operation),
    do: emit([:dawarich, :map, :post_commit_failure], %{count: 1}, %{operation: operation})

  def tile(conn, layer, started) do
    outcome =
      case conn.status do
        status when status in [200, 204] -> "success"
        304 -> "not_modified"
        400 -> "invalid"
        503 -> "failure"
        status -> "http_#{status}"
      end

    emit(@tile, %{count: 1, duration: elapsed(started)}, %{
      layer: String.trim_trailing(layer, "s") <> "_tiles",
      outcome: outcome
    })

    conn
  end

  defp elapsed(started), do: System.monotonic_time() - started

  defp emit(event, measurements, metadata) do
    :telemetry.execute(event, measurements, metadata)
  rescue
    _ -> :ok
  end

  def definitions do
    [
      sum("dawarich_map_point_moves_total",
        event_name: @move,
        measurement: :count,
        tags: [:outcome]
      ),
      distribution("dawarich_map_point_move_duration_seconds",
        event_name: @move,
        measurement: :duration,
        tags: [:outcome],
        unit: {:native, :second},
        reporter_options: [buckets: @duration]
      ),
      distribution("dawarich_map_point_move_lock_wait_seconds",
        event_name: @move,
        measurement: :lock_wait,
        tags: [:outcome],
        unit: {:native, :second},
        reporter_options: [buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3]]
      ),
      distribution("dawarich_map_point_move_track_points",
        event_name: @move,
        measurement: :track_points,
        reporter_options: [buckets: [1, 100, 1000, 10000, 50000, 100_000]]
      ),
      distribution("dawarich_map_point_move_track_segments",
        event_name: @move,
        measurement: :track_segments,
        reporter_options: [buckets: [0, 1, 5, 10, 25, 50, 100]]
      ),
      sum("dawarich_map_post_commit_failures_total",
        event_name: [:dawarich, :map, :post_commit_failure],
        measurement: :count,
        tags: [:operation]
      ),
      sum("dawarich_map_tile_requests_total",
        event_name: @tile,
        measurement: :count,
        tags: [:layer, :outcome]
      ),
      distribution("dawarich_map_tile_request_duration_seconds",
        event_name: @tile,
        measurement: :duration,
        tags: [:layer, :outcome],
        unit: {:native, :second},
        reporter_options: [buckets: @duration ++ [5]]
      )
    ]
  end
end
