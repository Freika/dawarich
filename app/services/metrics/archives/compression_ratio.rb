# frozen_string_literal: true

class Metrics::Archives::CompressionRatio
  def initialize(original_size:, compressed_size:)
    @ratio = compressed_size.to_f / original_size.to_f
  end

  def call
    return unless DawarichSettings.prometheus_exporter_enabled?

    metric_data = {
      type: 'histogram',
      name: 'dawarich_archive_compression_ratio',
      value: @ratio,
      buckets: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    }

    PrometheusExporter::Client.default.send_json(metric_data)
  rescue StandardError => e
    Rails.logger.error("Failed to send compression ratio metric: #{e.message}")
  end
end
