# frozen_string_literal: true

class Maps::TileUsage::Track
  def initialize(user_id, count = 1)
    @user_id = user_id
    @count = count
  end

  def call
    report_to_prometheus
    report_to_cache
  rescue StandardError => e
    Rails.logger.error("Failed to send tile usage metric: #{e.message}")
  end

  private

  def report_to_prometheus
    return unless DawarichSettings.prometheus_exporter_enabled?

    metric_data = {
      type: 'counter',
      name: 'dawarich_map_tiles_usage',
      value: @count
    }

    PrometheusExporter::Client.default.send_json(metric_data)
  end

  def report_to_cache
    today_key = "dawarich_map_tiles_usage:#{@user_id}:#{Time.zone.today}"

    current_value = (Rails.cache.read(today_key) || 0).to_i
    Rails.cache.write(today_key, current_value + @count, expires_in: 7.days)
  end
end
