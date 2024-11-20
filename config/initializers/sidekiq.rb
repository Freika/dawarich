# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] }

  if ENV['PROMETHEUS_EXPORTER_ENABLED'].to_s == 'true'
    require 'prometheus_exporter/instrumentation'

    config.server_middleware do |chain|
      chain.add PrometheusExporter::Instrumentation::Sidekiq
    end

    config.death_handlers << PrometheusExporter::Instrumentation::Sidekiq.death_handler

    config.on :startup do
      PrometheusExporter::Instrumentation::Process.start type: 'sidekiq'
      PrometheusExporter::Instrumentation::SidekiqProcess.start
      PrometheusExporter::Instrumentation::SidekiqQueue.start
      PrometheusExporter::Instrumentation::SidekiqStats.start
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] }
end
