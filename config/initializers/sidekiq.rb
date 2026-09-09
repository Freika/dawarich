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

# Reverse geocoding paces itself by sleeping the calling thread
# (Geocoding::RateLimiter). A thread parked there adds no throughput - the rate
# limit decides how fast lookups go out, not the pool size - so let the queue
# hold at most a third of the workers and leave the rest for imports, points
# and the priority queues. Raise REVERSE_GEOCODING_CONCURRENCY on an instance
# whose provider has no rate limit worth respecting.
#
# Written on every boot rather than only when it changes: sidekiq-limit_fetch
# stores the value in Redis with no expiry, so an instance that once ran the
# old komoot-only cap would keep that cap forever once the line setting it was
# removed. The floor of 1 matters for the same reason - limit_fetch treats 0 as
# "never acquire", which would strand the queue permanently.
if Sidekiq.server?
  require 'dawarich/idle_queue_check'
  Sidekiq::LimitFetch::Global::Selector.singleton_class.prepend(Dawarich::IdleQueueCheck)

  pool_size = ENV['BACKGROUND_PROCESSING_CONCURRENCY'].presence&.to_i || 10
  configured = ENV['REVERSE_GEOCODING_CONCURRENCY'].presence&.to_i

  Sidekiq::Queue['reverse_geocoding'].limit = [configured || pool_size / 3, 1].max
end
