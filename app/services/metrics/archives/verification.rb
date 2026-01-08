# frozen_string_literal: true

class Metrics::Archives::Verification
  def initialize(duration_seconds:, status:, check_name: nil)
    @duration_seconds = duration_seconds
    @status = status
    @check_name = check_name
  end

  def call
    return unless DawarichSettings.prometheus_exporter_enabled?

    # Duration histogram
    histogram_data = {
      type: 'histogram',
      name: 'dawarich_archive_verification_duration_seconds',
      value: @duration_seconds,
      labels: {
        status: @status
      },
      buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60]
    }

    PrometheusExporter::Client.default.send_json(histogram_data)

    # Failed check counter (if failure)
    if @status == 'failure' && @check_name
      counter_data = {
        type: 'counter',
        name: 'dawarich_archive_verification_failures_total',
        value: 1,
        labels: {
          check: @check_name  # e.g., 'count_mismatch', 'checksum_mismatch'
        }
      }

      PrometheusExporter::Client.default.send_json(counter_data)
    end
  rescue StandardError => e
    Rails.logger.error("Failed to send verification metric: #{e.message}")
  end
end
