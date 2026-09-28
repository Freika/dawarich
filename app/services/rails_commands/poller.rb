# frozen_string_literal: true

module RailsCommands
  module Poller
    POLL_SECONDS = 1
    BATCH = 100
    LEASE_SECONDS = 60
    MAX_ATTEMPTS = 25
    THREAD_NAME = 'rails-commands'
    THREAD_LOCK = Mutex.new

    class UnknownKind < StandardError; end
    class LeaseExpired < StandardError; end

    module_function

    def start
      return if Rails.env.test?

      THREAD_LOCK.synchronize do
        Thread.list.find { |thread| thread.name == THREAD_NAME } || spawn
      end
    end

    def stop
      thread = Thread.list.find { |candidate| candidate.name == THREAD_NAME }
      thread&.kill
      thread&.join
    end

    def drain_safely
      sleep(POLL_SECONDS) if drain_once.zero?
    rescue ActiveRecord::ActiveRecordError, PG::Error => e
      Rails.logger.warn("[RailsCommands] poll: #{e.class}")
      sleep(5)
    end

    def drain_once
      Rails.application.executor.wrap do
        rows = claim
        rows.each { |row| run(row) }
        rows.size
      end
    end

    def claim
      connection = ActiveRecord::Base.connection
      return [] unless connection.select_value("SELECT to_regclass('phoenix.rails_commands_dead') IS NOT NULL")

      connection.exec_query(<<~SQL.squish).to_a.sort_by { _1['id'] }
        UPDATE phoenix.rails_commands
        SET leased_until = now() + make_interval(secs => #{LEASE_SECONDS}), attempts = attempts + 1
        WHERE id IN (
          SELECT id FROM phoenix.rails_commands
          WHERE available_at <= now() AND (leased_until IS NULL OR leased_until < now())
          ORDER BY id LIMIT #{BATCH} FOR UPDATE SKIP LOCKED)
        RETURNING id, kind, payload::text AS payload, attempts, leased_until::text AS lease
      SQL
    end

    def run(row)
      if row['attempts'].to_i > MAX_ATTEMPTS
        return bury(row, MAX_ATTEMPTS, LeaseExpired.new("lease expired #{MAX_ATTEMPTS} times"))
      end

      error = attempt(row)
      error ? fail_attempt(row, error) : complete(row)
    rescue StandardError => e
      Rails.logger.warn(
        "[RailsCommands] #{row['id']} (#{row['kind']}) not settled: #{e.class}; retried after its lease"
      )
    end

    def attempt(row)
      handler = Registry.handler(row['kind'])
      raise UnknownKind, row['kind'] unless handler

      handler.call(JSON.parse(row['payload']))
      nil
    rescue StandardError => e
      e
    end

    def complete(row)
      result = execute('DELETE FROM phoenix.rails_commands WHERE id = ? AND leased_until = ?::timestamptz',
                       row['id'], row['lease'])
      return unless result.cmd_tuples.zero?

      Rails.logger.warn("[RailsCommands] #{row['id']} (#{row['kind']}) finished after its lease; it will run again")
    end

    def fail_attempt(row, error)
      attempts = row['attempts'].to_i
      return bury(row, attempts, error) if attempts >= MAX_ATTEMPTS

      execute(<<~SQL.squish, backoff_seconds(attempts), row['id'], row['lease'])
        UPDATE phoenix.rails_commands SET available_at = now() + make_interval(secs => ?), leased_until = NULL
        WHERE id = ? AND leased_until = ?::timestamptz
      SQL
      Rails.logger.warn("[RailsCommands] #{row['id']} (#{row['kind']}) failed attempt #{attempts}: #{error.class}")
    end

    def backoff_seconds(attempts) = (attempts**4) + 15

    def bury(row, attempts, error)
      last_error = "#{error.class}: #{error.message}".truncate(1000)
      execute(<<~SQL.squish, row['id'], row['lease'], attempts, last_error)
        WITH moved AS (
          DELETE FROM phoenix.rails_commands WHERE id = ? AND leased_until = ?::timestamptz
          RETURNING id, kind, payload, created_at)
        INSERT INTO phoenix.rails_commands_dead (id, kind, payload, attempts, last_error, created_at)
        SELECT id, kind, payload, ?, ?, created_at FROM moved
      SQL
      Rails.logger.error(
        "[RailsCommands] #{row['id']} (#{row['kind']}) dead after #{attempts} attempts: #{error.class}"
      )
    end

    def execute(sql, *binds)
      ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, *binds]))
    end

    def spawn
      thread = Thread.new { loop { drain_safely } }
      thread.name = THREAD_NAME
      thread
    end
    private_class_method :spawn
  end
end
