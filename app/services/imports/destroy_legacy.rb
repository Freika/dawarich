# frozen_string_literal: true

module Imports
  module DestroyLegacy
    class Busy < StandardError; end

    module_function

    def coordinated?(import)
      import.gpx? &&
        ActiveRecord::Base.connection.select_value("SELECT to_regclass('phoenix.import_destroy_runs') IS NOT NULL")
    end

    def perform(import, expected_user_id:, event_id:, job_event_id:)
      with_lock(import.id) do
        result = ActiveRecord::Base.transaction { admission(import, expected_user_id, event_id, job_event_id) }
        if result && result.first == :destroy
          yield
          complete(import.id, expected_user_id, result.last)
        end
      end
    end

    def with_lock(import_id)
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        key = connection.quote("phoenix-import:#{import_id}")
        locked = connection.select_value("SELECT pg_try_advisory_lock(hashtextextended(#{key},0))")
        raise Busy, 'Another import attempt is running' unless locked

        begin
          yield
        ensure
          connection.select_value("SELECT pg_advisory_unlock(hashtextextended(#{key},0))")
        end
      end
    end

    def admission(import, expected_user_id, event_id, job_event_id)
      owner = JobOwnership.lock_owner('command:imports.destroy')
      import.reload(lock: true)
      return unless import.user_id == expected_user_id

      import.association(:user).reset
      return unless User.exists?(id: expected_user_id)

      if foreign_children?(import)
        Rails.logger.warn("[imports] import #{import.id} not deleted: it holds another user's data")
        return
      end

      row = receipt(import.id)
      return if row && (row['user_id'].to_i != expected_user_id || row['phase'] == 'removed')
      return if event_id && row && row['event_id'] != event_id

      event_id ||= row&.fetch('event_id') || job_event_id
      insert_receipt(import, event_id) unless row
      if owner == :oban && !(row && row['native_fallback'])
        JobCommands.forward('imports.destroy', { 'import_id' => import.id, 'user_id' => import.user_id },
                            event_id:, aggregate_id: import.id, producer: 'Imports::DestroyJob',
                            dedupe_key: "destroy-import:#{import.id}")
        [:forwarded, event_id]
      else
        [:destroy, event_id]
      end
    end

    def foreign_children?(import)
      [Point, Visit, Track, Place].any? do |klass|
        klass.where(import_id: import.id).where.not(user_id: import.user_id).exists?
      end
    end

    def receipt(import_id)
      ActiveRecord::Base.connection.select_one(<<~SQL.squish)
        SELECT * FROM phoenix.import_destroy_runs WHERE import_id=#{Integer(import_id)} FOR UPDATE
      SQL
    end

    def complete(import_id, user_id, event_id)
      connection = ActiveRecord::Base.connection
      connection.execute(<<~SQL.squish)
        UPDATE phoenix.import_destroy_runs SET phase='removed',updated_at=now()
        WHERE import_id=#{Integer(import_id)} AND user_id=#{Integer(user_id)}
          AND event_id=#{connection.quote(event_id)}
          AND NOT EXISTS(SELECT 1 FROM imports WHERE id=#{Integer(import_id)})
      SQL
    end

    def insert_receipt(import, event_id)
      connection = ActiveRecord::Base.connection
      connection.execute(<<~SQL.squish)
        INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id)
        VALUES(#{import.id},#{import.user_id},#{connection.quote(event_id)})
        ON CONFLICT(import_id) DO NOTHING
      SQL
    end

    private_class_method :admission, :insert_receipt
  end
end
