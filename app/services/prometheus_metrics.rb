# frozen_string_literal: true

require 'net/http'
require 'uri'

class PrometheusMetrics
  class << self
    def fetch_data
      return { success: false, error: 'Prometheus exporter not enabled' } unless prometheus_enabled?

      host = ENV.fetch('PROMETHEUS_EXPORTER_HOST', 'localhost')
      port = ENV.fetch('PROMETHEUS_EXPORTER_PORT', 9394)

      begin
        response = Net::HTTP.get_response(URI("http://#{host}:#{port}/metrics"))

        if response.code == '200'
          { success: true, data: response.body }
        else
          { success: false, error: "Prometheus server returned #{response.code}" }
        end
      rescue StandardError => e
        Rails.logger.error "Failed to fetch Prometheus metrics: #{e.message}"
        { success: false, error: e.message }
      end
    end

    private

    def prometheus_enabled?
      DawarichSettings.prometheus_exporter_enabled?
    end
  end
end
