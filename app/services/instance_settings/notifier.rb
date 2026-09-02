# frozen_string_literal: true

module InstanceSettings
  # Carries "this setting changed" between processes. Puma and Sidekiq run in
  # separate containers, so a value saved in the web process is invisible to the
  # worker until something tells it to look again.
  #
  # Only the key name travels. Publishing the value would put a decrypted API key
  # on a Redis channel for no gain — subscribers can read it themselves.
  module Notifier
    CHANNEL = 'dawarich:instance_settings'
    RECONNECT_BACKOFF = 2.seconds

    class << self
      def publish(key)
        redis.publish(CHANNEL, { 'key' => key.to_s }.to_json)
      rescue StandardError => e
        # A settings save must not fail because the notification did. The TTL
        # backstop in Resolver picks up the change regardless.
        Rails.logger.warn("[InstanceSettings] publish failed: #{e.class}: #{e.message}")
      end

      def handle_message(payload)
        parsed = JSON.parse(payload)
        return unless parsed.is_a?(Hash) && parsed['key'].present?

        Resolver.reset!
      rescue JSON::ParserError => e
        Rails.logger.warn("[InstanceSettings] ignoring malformed notification: #{e.message}")
      end

      # Started from Puma's on_worker_boot and Sidekiq's :startup, never from an
      # initializer: config/puma.rb sets preload_app!, so a thread spawned during
      # preload lives in the master and dies at fork, leaving every request-serving
      # worker permanently stale.
      def start
        return if Rails.env.test?
        return if @thread&.alive?

        @thread = Thread.new { listen_forever }
        @thread.name = 'instance-settings-subscriber'
        @thread
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', nil))
      end

      private

      def listen_forever
        loop { listen_once }
      end

      # One subscribe attempt. Split out so the reconnect behaviour can be
      # tested directly: stubbing `loop` on this module to make the method
      # terminate would mean a rewrite to `while true` hangs the suite instead
      # of failing it.
      def listen_once
        subscriber = Redis.new(url: ENV.fetch('REDIS_URL', nil))
        subscriber.subscribe(CHANNEL) do |on|
          on.message { |_channel, payload| handle_message(payload) }
        end
      rescue StandardError => e
        Rails.logger.warn("[InstanceSettings] subscriber reconnecting after #{e.class}: #{e.message}")
      ensure
        sleep RECONNECT_BACKOFF
      end
    end
  end
end
