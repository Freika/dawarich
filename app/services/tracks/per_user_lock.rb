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

    class AcquisitionTimeout < StandardError; end

    def self.with_user_lock(user_id, timeout: DEFAULT_ACQUIRE_TIMEOUT, ttl: DEFAULT_TTL)
      key = "#{NAMESPACE}:#{user_id}"
      token = SecureRandom.uuid
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      acquire!(key, token, ttl, timeout, user_id, started_at)

      heartbeat = start_heartbeat(key, token, ttl, user_id)
      begin
        yield
      ensure
        stop_heartbeat(heartbeat)
        release(key, token)
      end
    end

    def self.acquire!(key, token, ttl, timeout, user_id, started_at)
      deadline = started_at + timeout
      ttl_ms = (ttl * 1000).to_i

      loop do
        acquired = Sidekiq.redis { |r| r.set(key, token, nx: true, px: ttl_ms) }
        if acquired
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

    def self.start_heartbeat(key, token, ttl, user_id)
      interval = [ttl / RENEW_DIVISOR, POLL_INTERVAL].max
      ttl_ms = (ttl * 1000).to_i
      stop = Queue.new

      thread = Thread.new do
        renew_errors = 0
        loop do
          break if stop.pop(timeout: interval)

          begin
            break if lock_lost?(key, token, ttl_ms, user_id)

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

    def self.lock_lost?(key, token, ttl_ms, user_id)
      return false if renew(key, token, ttl_ms)

      Rails.logger.warn("event=tracks.per_user_lock_renew_lost user_id=#{user_id}")
      true
    end

    def self.renew(key, token, ttl_ms)
      result = Sidekiq.redis { |r| r.call('EVAL', RENEW_LUA, 1, key, token, ttl_ms.to_s) }
      result.to_i == 1
    end

    def self.release(key, token)
      Sidekiq.redis { |r| r.call('EVAL', RELEASE_LUA, 1, key, token) }
    end
  end
end
