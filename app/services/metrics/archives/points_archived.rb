# frozen_string_literal: true

class Metrics::Archives::PointsArchived
  def initialize(count:, operation:)
    @count = count
    @operation = operation # 'added' or 'removed'
  end

  def call
    return unless DawarichSettings.prometheus_exporter_enabled?

    metric_data = {
      type: 'counter',
      name: 'dawarich_archive_points_total',
      value: @count,
      labels: {
        operation: @operation
      }
    }

    PrometheusExporter::Client.default.send_json(metric_data)
  rescue StandardError => e
    Rails.logger.error("Failed to send points archived metric: #{e.message}")
  end
end
