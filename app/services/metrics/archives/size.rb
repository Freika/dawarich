# frozen_string_literal: true

class Metrics::Archives::Size
  def initialize(size_bytes:)
    @size_bytes = size_bytes
  end

  def call
    return unless DawarichSettings.prometheus_exporter_enabled?

    metric_data = {
      type: 'histogram',
      name: 'dawarich_archive_size_bytes',
      value: @size_bytes,
      buckets: [
        1_000_000,      # 1 MB
        10_000_000,     # 10 MB
        50_000_000,     # 50 MB
        100_000_000,    # 100 MB
        500_000_000,    # 500 MB
        1_000_000_000   # 1 GB
      ]
    }

    PrometheusExporter::Client.default.send_json(metric_data)
  rescue StandardError => e
    Rails.logger.error("Failed to send archive size metric: #{e.message}")
  end
end
