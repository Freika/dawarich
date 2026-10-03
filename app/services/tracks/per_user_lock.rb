# frozen_string_literal: true

module Tracks
  module PerUserLock
    NAMESPACE = 'tracks:per_user_lock'
    DEFAULT_ACQUIRE_TIMEOUT = 30.0
    DEFAULT_TTL = 60.0
    RENEW_DIVISOR = 3.0
    MAX_RENEW_ERRORS = 3
    POLL_INTERVAL = 0.1
    LOCK_WAIT_WARN_SECONDS = 1.0

    class AcquisitionTimeout < StandardError; end

    module RedisStore
      RELEASE_LUA = <<~LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      LUA

      RENEW_LUA = <<~LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("pexpire", KEYS[1], ARGV[2])
        else
          return 0
        end
      LUA

      module_function

      def acquire(key, token, ttl) = Sidekiq.redis { |r| r.set(key, token, nx: true, px: (ttl * 1000).to_i) }

      def renew(key, token, ttl)
        Sidekiq.redis { |r| r.call('EVAL', RENEW_LUA, 1, key, token, (ttl * 1000).to_i.to_s) }.to_i == 1
      end

      def release(key, token) = Sidekiq.redis { |r| r.call('EVAL', RELEASE_LUA, 1, key, token) }
    end

    def self.store = PhoenixLease.table? ? PhoenixLease : RedisStore

    def self.with_user_lock(user_id, timeout: DEFAULT_ACQUIRE_TIMEOUT, ttl: DEFAULT_TTL)
      key = "#{NAMESPACE}:#{user_id}"
      token = SecureRandom.uuid
      store = self.store
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      acquire!(store, key, token, ttl, timeout, user_id, started_at)

      begin
        heartbeat = start_heartbeat(store, key, token, ttl, user_id)
        yield
      ensure
        stop_heartbeat(heartbeat)
        store.release(key, token)
      end
    end

    def self.acquire!(store, key, token, ttl, timeout, user_id, started_at)
      deadline = started_at + timeout

      loop do
        if store.acquire(key, token, ttl)
          warn_on_contention(user_id, started_at)
          return true
        end

        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          raise AcquisitionTimeout,
                "Tracks::PerUserLock: could not acquire lock for user_id=#{user_id} " \
                "within #{timeout}s"
        end

        sleep POLL_INTERVAL
      end
    end

    def self.warn_on_contention(user_id, started_at)
      waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      return if waited < LOCK_WAIT_WARN_SECONDS

      Rails.logger.warn(
        "event=tracks.per_user_lock_contention user_id=#{user_id} " \
        "waited_seconds=#{waited.round(3)}"
      )
    end

    def self.start_heartbeat(store, key, token, ttl, user_id)
      interval = [ttl / RENEW_DIVISOR, POLL_INTERVAL].max
      stop = Queue.new

      thread = Thread.new do
        renew_errors = 0
        loop do
          break if stop.pop(timeout: interval)

          begin
            break if lock_lost?(store, key, token, ttl, user_id)

            renew_errors = 0
          rescue StandardError => e
            renew_errors += 1
            Rails.logger.warn(
              "event=tracks.per_user_lock_renew_error user_id=#{user_id} " \
              "consecutive=#{renew_errors} error=#{e.class}: #{e.message}"
            )
            if renew_errors >= MAX_RENEW_ERRORS
              Rails.logger.warn(
                "event=tracks.per_user_lock_renew_lost user_id=#{user_id} reason=consecutive_renew_errors"
              )
              break
            end
          end
        end
      end

      { thread: thread, stop: stop }
    end

    def self.stop_heartbeat(heartbeat)
      return unless heartbeat

      heartbeat[:stop] << :stop
      heartbeat[:thread].join
    end

    def self.lock_lost?(store, key, token, ttl, user_id)
      return false if store.renew(key, token, ttl)

      Rails.logger.warn("event=tracks.per_user_lock_renew_lost user_id=#{user_id}")
      true
    end
  end
end
