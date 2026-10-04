# frozen_string_literal: true

module Imports
  module NormalResume
    class Busy < StandardError; end

    module_function

    def call(payload)
      return unless matching_receipt(payload)

      JobCommands.enqueue_after_commit(nil) { Import::NormalResumeJob.perform_later(payload) }
    end

    def perform(payload)
      name = "import:#{Integer(payload.fetch('import_id'))}"
      PhoenixLease.hold(name, Busy.new('Another import attempt is running')) do
        action = ActiveRecord::Base.transaction { prepare(payload) }
        next unless action == :process

        import = Import.find_by(id: payload.fetch('import_id'), user_id: payload.fetch('user_id'))
        Time.use_zone(payload.fetch('time_zone')) do
          I18n.with_locale(import.user.locale) { import.process! }
        end
        ActiveRecord::Base.transaction { finish(payload, 'completed') }
      end
    end

    def prepare(payload)
      receipt = matching_receipt(payload, lock: true)
      return unless receipt

      import = Import.where(id: payload.fetch('import_id'), user_id: payload.fetch('user_id')).lock.first
      gpx = import && ImportCommands.native_gpx?(import)
      type = gpx ? 'imports.process_gpx' : 'imports.process_normal'
      owner = JobOwnership.lock_owner("command:#{type}")
      if !import || import.completed? || import.deleting? || import.user.deleted_at
        finish(payload, 'completed')
      elsif owner == :oban && !receipt['native_fallback'] && (gpx || ProcessCommands.native?(import))
        forward(payload, type, gpx ? 'gpx' : 'normal')
      else
        :process
      end
    end

    def matching_receipt(payload, lock: false)
      statement = <<~SQL.squish
        SELECT * FROM phoenix.import_handoffs WHERE event_id=? AND import_id=? AND user_id=?
        AND time_zone=? AND state='pending'
      SQL
      statement += ' FOR UPDATE' if lock
      ActiveRecord::Base.connection.select_one(sql(statement, payload.fetch('event_id'),
                                                   payload.fetch('import_id'), payload.fetch('user_id'),
                                                   payload.fetch('time_zone')))
    end

    def forward(payload, type, lane)
      event_id = SecureRandom.uuid
      ActiveRecord::Base.connection.execute(sql('DELETE FROM phoenix.import_runs WHERE import_id=? AND event_id=?',
                                                payload.fetch('import_id'), payload.fetch('event_id')))
      JobCommands.forward(type, payload.except('event_id'), event_id:,
                          aggregate_id: payload.fetch('import_id'), producer: 'Imports::NormalResume',
                          dedupe_key: "process-#{lane}:#{payload.fetch('import_id')}")
      ActiveRecord::Base.connection.execute(sql(<<~SQL.squish, event_id, payload.fetch('event_id')))
        UPDATE phoenix.import_handoffs SET state='forwarded',forwarded_event_id=?,updated_at=now()
        WHERE event_id=? AND state='pending'
      SQL
      :forwarded
    end

    def finish(payload, state)
      ActiveRecord::Base.connection.execute(sql(<<~SQL.squish, state, payload.fetch('event_id')))
        UPDATE phoenix.import_handoffs SET state=?,updated_at=now() WHERE event_id=? AND state='pending'
      SQL
      :completed
    end

    def sql(statement, *values) = ActiveRecord::Base.sanitize_sql_array([statement, *values])
    private_class_method :prepare, :matching_receipt, :forward, :finish, :sql
  end
end
