# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] }
  config.logger = Sidekiq::Logger.new($stdout)

  if ENV['PROMETHEUS_EXPORTER_ENABLED'].to_s == 'true'
    require 'prometheus_exporter/instrumentation'

    # Add middleware for collecting job-level metrics
    config.server_middleware do |chain|
      chain.add PrometheusExporter::Instrumentation::Sidekiq
    end

    # Capture metrics for failed jobs
    config.death_handlers << PrometheusExporter::Instrumentation::Sidekiq.death_handler

    # Start Prometheus instrumentation
    config.on :startup do
      PrometheusExporter::Instrumentation::SidekiqProcess.start
      PrometheusExporter::Instrumentation::SidekiqQueue.start
      PrometheusExporter::Instrumentation::SidekiqStats.start
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] }
end

Sidekiq::Queue['reverse_geocoding'].limit = 1 if Sidekiq.server? && DawarichSettings.photon_uses_komoot_io?
