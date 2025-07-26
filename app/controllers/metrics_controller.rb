# frozen_string_literal: true

class MetricsController < ApplicationController
  http_basic_authenticate_with name: ENV['METRICS_USERNAME'], password: ENV['METRICS_PASSWORD'], only: :index

  def index
    result = PrometheusMetrics.fetch_data

    if result[:success]
      render plain: result[:data], content_type: 'text/plain'
    elsif result[:error] == 'Prometheus exporter not enabled'
      head :not_found
    else
      head :service_unavailable
    end
  end
end
