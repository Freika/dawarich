# frozen_string_literal: true

class TileUsage::Track
  def initialize(count = 1)
    @count = count
  end

  def call
    metric_data = {
      type: 'counter',
      name: 'dawarich_map_tiles',
      value: @count
    }

    PrometheusExporter::Client.default.send_json(metric_data)
  rescue StandardError => e
    Rails.logger.error("Failed to send tile usage metric: #{e.message}")
  end
end
