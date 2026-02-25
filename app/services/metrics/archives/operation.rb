# frozen_string_literal: true

class Metrics::Archives::Operation
  OPERATIONS = %w[archive verify clear restore].freeze

  def initialize(operation:, status:)
    @operation = operation
    @status = status # 'success' or 'failure'
  end

  def call
    return unless DawarichSettings.prometheus_exporter_enabled?

    metric_data = {
      type: 'counter',
      name: 'dawarich_archive_operations_total',
      value: 1,
      labels: {
        operation: @operation,
        status: @status
      }
    }

    PrometheusExporter::Client.default.send_json(metric_data)
  rescue StandardError => e
    Rails.logger.error("Failed to send archive operation metric: #{e.message}")
  end
end
