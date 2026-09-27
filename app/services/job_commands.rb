# frozen_string_literal: true

module JobCommands
  COMMANDS = {
    'users.explore_features_mail' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        I18n.with_locale(payload['locale']) do
          Users::MailerSendingJob.set(wait_until: at).perform_later(payload['user_id'], 'explore_features')
        end
      }
    },
    'trips.calculate' => {
      version: 1,
      sidekiq: ->(payload, _at) { Trips::CalculateAllJob.perform_later(payload['trip_id'], payload['distance_unit']) }
    }
  }.freeze

  module_function

  def produce(type, payload, aggregate_id:, producer:, scheduled_at: Time.current, dedupe_key: nil)
    command = COMMANDS.fetch(type)
    ActiveRecord::Base.transaction do
      if JobOwnership.lock_owner("command:#{type}") == :oban
        insert(type, payload, event_id: SecureRandom.uuid, aggregate_id:, producer:, scheduled_at:, dedupe_key:)
        :outbox
      else
        command.fetch(:sidekiq).call(payload, scheduled_at)
        :sidekiq
      end
    end
  end

  def forward(type, payload, event_id:, aggregate_id:, producer:, scheduled_at: Time.current, dedupe_key: nil)
    insert(type, payload, event_id:, aggregate_id:, producer:, scheduled_at:, dedupe_key:)
  end

  def insert(type, payload, event_id:, aggregate_id:, producer:, scheduled_at:, dedupe_key:)
    JobOutbox.insert_all(
      [{ event_id:, command_type: type, command_version: COMMANDS.fetch(type).fetch(:version), payload:,
         metadata: { 'producer' => producer }, aggregate_id:, dedupe_key:, scheduled_at: }]
    ).length
  end

  private_class_method :insert

  def cancel_pending(type, aggregate_id)
    JobOutbox.pending.where(command_type: type, aggregate_id:).delete_all
  end

  def rehome!(type, by:)
    command = COMMANDS.fetch(type)
    ActiveRecord::Base.transaction do
      JobOwnership.release!("command:#{type}", by:)
      pending = JobOutbox.pending.where(command_type: type, command_version: command.fetch(:version))
      total = pending.count
      rows = pending.lock('FOR UPDATE SKIP LOCKED').to_a
      rows.each { |row| command.fetch(:sidekiq).call(row.payload, row.scheduled_at) }
      JobOutbox.where(event_id: rows.map(&:event_id)).delete_all
      { moved: rows.size, left: total - rows.size }
    end
  end

  def replay!(event_id, actor:, reason:)
    ActiveRecord::Base.transaction do
      row = JobOutbox.lock.find(event_id)
      unless row.state == 'quarantined'
        raise ArgumentError, "#{event_id} is #{row.state}; only quarantined commands can be replayed"
      end

      row.update!(state: 'pending', error_code: nil)
      sql = <<~SQL.squish
        INSERT INTO phoenix.job_outbox_replays (event_id, actor, reason) VALUES (?, ?, ?)
      SQL
      ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, event_id, actor, reason]))
    end
  end
end
