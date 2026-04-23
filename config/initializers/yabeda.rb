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
end

Yabeda.configure! if defined?(Yabeda)

# Register the Prometheus adapter so metric emissions reach prometheus-client.
require 'yabeda/prometheus'
