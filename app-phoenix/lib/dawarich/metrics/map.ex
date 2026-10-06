defmodule Dawarich.Metrics.Map do
  @moduledoc false
  import Telemetry.Metrics

  @move [:dawarich, :map, :move]
  @tile [:dawarich, :map, :tile]
  @duration [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3]

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
