# frozen_string_literal: true

class MetricsController < ApplicationController
  before_action :ensure_metrics_credentials_configured!, only: :index

  http_basic_authenticate_with(
    name: METRICS_USERNAME.to_s,
    password: METRICS_PASSWORD.to_s,
    only: :index,
    if: -> { METRICS_USERNAME.present? && METRICS_PASSWORD.present? }
  )

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

  private

  # audit M-3: refuse to serve /metrics if credentials weren't configured.
  # The previous defaults exposed metrics with prometheus/prometheus.
  def ensure_metrics_credentials_configured!
    return if METRICS_USERNAME.present? && METRICS_PASSWORD.present?

    head :service_unavailable
  end
end
