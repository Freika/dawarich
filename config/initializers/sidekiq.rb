# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'], db: ENV.fetch('RAILS_JOB_QUEUE_DB', 1) }
  config.logger = Sidekiq::Logger.new($stdout)

  next unless DawarichSettings.prometheus_exporter_enabled?

  # yabeda-sidekiq auto-registers server middleware and the death handler on require.
  # Keep the cluster-metrics poller (queue latency/depth/process counts) running in
  # the Sidekiq server process — web workers should not poll Redis for these.
  require 'yabeda/sidekiq'

  # Start the standalone Prometheus exporter inside the Sidekiq container on port 9394,
  # wrapped in HTTP basic auth.
  config.on(:startup) do
    require 'rackup'
    require 'webrick'
    require 'yabeda/prometheus/exporter'
    require 'dawarich/metrics_basic_auth'

    port = ENV.fetch('PROMETHEUS_EXPORTER_PORT', 9394).to_i
    rack_app = Dawarich::MetricsBasicAuth.new(Yabeda::Prometheus::Exporter.rack_app)
    Thread.new do
      Rackup::Handler::WEBrick.run(
        rack_app,
        Port: port,
        BindAddress: '0.0.0.0',
        Logger: WEBrick::Log.new(File::NULL),
        AccessLog: []
      )
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'], db: ENV.fetch('RAILS_JOB_QUEUE_DB', 1) }
end

Sidekiq::Queue['reverse_geocoding'].limit = 1 if Sidekiq.server? && DawarichSettings.photon_uses_komoot_io?
