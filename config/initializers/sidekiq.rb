# frozen_string_literal: true

Yabeda::Sidekiq.config.declare_process_metrics = true if ENV['SIDEKIQ_EMBEDDED'] == 'true'

Sidekiq::Cron.configuration.cron_poll_interval =
  Integer(ENV.fetch('SIDEKIQ_CRON_POLL_INTERVAL', ''), exception: false) || 30

Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'], db: ENV.fetch('RAILS_JOB_QUEUE_DB', 1) }
  config.logger = Sidekiq::Logger.new($stdout)

  # The worker process caches instance settings independently of the web
  # process, so it needs its own subscriber to notice a change made in the UI.
  config.on(:startup) do
    InstanceSettings::Notifier.start
  rescue StandardError => e
    Rails.logger.warn("[InstanceSettings] subscriber failed to start: #{e.class}: #{e.message}")
  end

  config.on(:startup) do
    Dawarich::ReverseGeocodingLimits.configure!(config)
  rescue StandardError => e
    Rails.logger.warn("[ReverseGeocodingLimits] failed to apply: #{e.class}: #{e.message}")
  end

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
    rescue StandardError => e
      Rails.logger.error(
        "[Sidekiq metrics] WEBrick exporter on :#{port} crashed: " \
        "#{e.class}: #{e.message}"
      )
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'], db: ENV.fetch('RAILS_JOB_QUEUE_DB', 1) }
end

if Sidekiq.server?
  require 'dawarich/idle_queue_check'
  Sidekiq::LimitFetch::Global::Selector.singleton_class.prepend(Dawarich::IdleQueueCheck)
end
