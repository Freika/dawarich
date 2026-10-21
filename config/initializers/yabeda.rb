# frozen_string_literal: true

Yabeda.configure do
  group :dawarich_archive do
    counter :operations_total,
            comment: 'Archive operations by type and outcome',
            tags: %i[operation status]

    counter :points_total,
            comment: 'Points archived or removed',
            tags: %i[operation]

    histogram :compression_ratio,
              comment: 'Compressed / original size ratio',
              buckets: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

    counter :count_mismatches_total,
            comment: 'Count mismatches between DB and archive',
            tags: %i[year month]

    gauge :count_difference,
          comment: 'Absolute difference between expected and actual archived points. ' \
                   'user_id label is intentional and low-cardinality given Dawarich user scale.',
          tags: %i[user_id]

    histogram :size_bytes,
              comment: 'Archive size in bytes',
              buckets: [1_000_000, 10_000_000, 50_000_000, 100_000_000, 500_000_000, 1_000_000_000]

    histogram :verification_duration_seconds,
              comment: 'Archive verification duration',
              tags: %i[status],
              buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60]

    counter :verification_failures_total,
            comment: 'Archive verification failures by check',
            tags: %i[check]
  end

  group :dawarich_map do
    counter :point_moves_total,
            comment: 'Point position mutations by outcome',
            tags: %i[outcome]

    histogram :point_move_duration_seconds,
              comment: 'End-to-end synchronous Point move duration',
              tags: %i[outcome],
              buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3]

    histogram :point_move_lock_wait_seconds,
              comment: 'Time spent acquiring Point and Track row locks',
              tags: %i[outcome],
              buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3]

    histogram :point_move_track_points,
              comment: 'Point count of synchronously recalculated Tracks',
              buckets: [1, 100, 1_000, 10_000, 50_000, 100_000]

    histogram :point_move_track_segments,
              comment: 'TrackSegment count touched by synchronous Point moves',
              buckets: [0, 1, 5, 10, 25, 50, 100]

    counter :post_commit_failures_total,
            comment: 'Map cache invalidation or publication failures after a successful commit',
            tags: %i[operation]

    counter :tile_requests_total,
            comment: 'Point and Track vector-tile requests by HTTP outcome',
            tags: %i[layer outcome]

    histogram :tile_request_duration_seconds,
              comment: 'Point and Track vector-tile request duration',
              tags: %i[layer outcome],
              buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 3, 5]
  end

  group :dawarich_imports do
    gauge :extraction_oldest_age_seconds,
          comment: 'Age of the oldest additional-data extraction in each in-flight state',
          tags: %i[state]

    gauge :extractions_stalled,
          comment: 'In-flight extractions past the stall window or without a readable start time'
  end
end

Yabeda.configure! if defined?(Yabeda)

# Register the Prometheus adapter so metric emissions reach prometheus-client.
require 'yabeda/prometheus'

if defined?(Rails.logger) &&
   DawarichSettings.prometheus_exporter_enabled? &&
   METRICS_USERNAME == 'prometheus' &&
   METRICS_PASSWORD == 'prometheus'
  Rails.logger.warn(
    '[Prometheus] METRICS_USERNAME/METRICS_PASSWORD are at default values. ' \
    'Set them to non-default credentials before exposing /metrics publicly.'
  )
end
