# frozen_string_literal: true

module Trips
  module Detection
    # A per-user Postgres advisory lock so two Trip Detection runs of one user
    # never reconcile at the same time. Keys are built like Users::DataLock's,
    # in a namespace of their own.
    module RunLock
      extend Visits::AdvisoryLockable

      NAMESPACE = 0x5452_4950_0000_0000 # "TRIP"
      MAX_USER_ID = (1 << 32) - 1

      # Yields and returns true when the lock was free; returns false without
      # yielding when another run holds it.
      def self.try_with(user_id)
        unless advisory_locks_enabled?
          yield
          return true
        end

        key = lock_key(user_id)
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          return false unless connection.select_value("SELECT pg_try_advisory_lock(#{key})")

          begin
            yield
            true
          ensure
            release(connection, key)
          end
        end
      end

      def self.release(connection, key)
        connection.execute("SELECT pg_advisory_unlock(#{key})")
      rescue ActiveRecord::ActiveRecordError, PG::Error => e
        Rails.logger.warn("Trips::Detection::RunLock: unlock failed: #{e.class}: #{e.message}")
        connection.throw_away!
      end
      private_class_method :release

      def self.lock_key(user_id)
        id = Integer(user_id)
        raise ArgumentError, 'user_id is outside the supported lock-key range' unless id.between?(0, MAX_USER_ID)

        NAMESPACE | id
      end
      private_class_method :lock_key
    end
  end
end
