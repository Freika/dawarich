# frozen_string_literal: true

class Metrics::Archives::CountMismatch
  def initialize(user_id:, year:, month:, expected:, actual:)
    @user_id = user_id
    @year = year
    @month = month
    @expected = expected
    @actual = actual
  end

  def call
    return unless DawarichSettings.prometheus_exporter_enabled?

    # Counter for critical errors
    counter_data = {
      type: 'counter',
      name: 'dawarich_archive_count_mismatches_total',
      value: 1,
      labels: {
        year: @year.to_s,
        month: @month.to_s
      }
    }

    PrometheusExporter::Client.default.send_json(counter_data)

    # Gauge showing the difference
    gauge_data = {
      type: 'gauge',
      name: 'dawarich_archive_count_difference',
      value: (@expected - @actual).abs,
      labels: {
        user_id: @user_id.to_s
      }
    }

    PrometheusExporter::Client.default.send_json(gauge_data)
  rescue StandardError => e
    Rails.logger.error("Failed to send count mismatch metric: #{e.message}")
  end
end
