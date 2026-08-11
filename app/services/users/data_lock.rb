# frozen_string_literal: true

module Users
  module DataLock
    NAMESPACE = 0x4441_5741_0000_0000
    MAX_USER_ID = (1 << 32) - 1

    def self.with_shared(user_id, &)
      with_lock(user_id, shared: true, &)
    end

    def self.with_exclusive(user_id, &)
      with_lock(user_id, shared: false, &)
    end

    def self.with_lock(user_id, shared:)
      key = lock_key(user_id)
      lock_function = shared ? 'pg_advisory_lock_shared' : 'pg_advisory_lock'
      unlock_function = shared ? 'pg_advisory_unlock_shared' : 'pg_advisory_unlock'

      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("SELECT #{lock_function}(#{key})")

        begin
          yield
        ensure
          connection.execute("SELECT #{unlock_function}(#{key})")
        end
      end
    end
    private_class_method :with_lock

    def self.lock_key(user_id)
      id = Integer(user_id)
      raise ArgumentError, 'user_id is outside the supported lock-key range' unless id.between?(0, MAX_USER_ID)

      NAMESPACE | id
    end
    private_class_method :lock_key
  end
end
