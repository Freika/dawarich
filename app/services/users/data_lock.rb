# frozen_string_literal: true

module Users
  module DataLock
    extend Visits::AdvisoryLockable

    NAMESPACE = 0x4441_5741_0000_0000
    MAX_USER_ID = (1 << 32) - 1

    class Busy < StandardError; end

    def self.with_shared(user_id, &)
      return yield unless advisory_locks_enabled?

      key = lock_key(user_id)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("SELECT pg_advisory_lock_shared(#{key})")
        hold(connection, "SELECT pg_advisory_unlock_shared(#{key})", &)
      end
    end

    def self.with_exclusive(user_id, &)
      return yield unless advisory_locks_enabled?

      key = lock_key(user_id)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        unless connection.select_value("SELECT pg_try_advisory_lock(#{key})")
          raise Busy, "user #{user_id} has an import in progress"
        end

        hold(connection, "SELECT pg_advisory_unlock(#{key})", &)
      end
    end

    def self.hold(connection, unlock_sql)
      yield
    ensure
      begin
        connection.execute(unlock_sql)
      rescue ActiveRecord::ActiveRecordError, PG::Error => e
        Rails.logger.warn("Users::DataLock: unlock failed: #{e.class}: #{e.message}")
        connection.throw_away!
      end
    end
    private_class_method :hold

    def self.lock_key(user_id)
      id = Integer(user_id)
      raise ArgumentError, 'user_id is outside the supported lock-key range' unless id.between?(0, MAX_USER_ID)

      NAMESPACE | id
    end
    private_class_method :lock_key
  end
end
