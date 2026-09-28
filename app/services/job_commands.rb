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
    },
    'imports.update_points_count' => {
      version: 1,
      sidekiq: ->(payload, _at) { Import::UpdatePointsCountJob.perform_later(payload['import_id']) }
    },
    'imports.airtrail_flights' => {
      version: 1,
      sidekiq: ->(payload, _at) { AirTrail::ImportFlightsJob.perform_later(payload['user_id']) }
    },
    'achievements.check' => {
      version: 1,
      sidekiq: lambda { |payload, _at|
        Achievements::CheckJob.perform_later(payload['user_id'], notify: payload['notify'],
                                                                   oldest_timestamp: payload['oldest_timestamp'])
      }
    },
    'areas.relabel_visits' => {
      version: 1,
      sidekiq: ->(payload, _at) { Areas::RelabelVisitsJob.perform_later(payload['area_id']) }
    },
    'exports.points' => {
      version: 1,
      sidekiq: lambda { |payload, _at|
        JobCommands.enqueue_after_commit(nil) { ExportJob.perform_later(payload.fetch('export_id')) }
      }
    },
    'mail.family_invitation' => {
      version: 1,
      sidekiq: lambda { |payload, _at|
        I18n.with_locale(payload['locale']) do
          Family::Invitations::SendingJob.perform_later(payload.fetch('invitation_id'))
        end
      }
    },
    'mail.family_lapse' => {
      version: 1,
      sidekiq: lambda { |payload, _at|
        JobCommands.enqueue_after_commit(payload['locale']) do
          Families::LapseNotificationJob.perform_later(payload.fetch('user_id'), payload.fetch('family_id'))
        end
      }
    },
    **UserMailCommands::TYPES.to_h { |email_type, type| [type, { version: 1, sidekiq: UserMailCommands.legacy(email_type) }] }
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

  def enqueue_after_commit(locale, &enqueue)
    return I18n.with_locale(locale, &enqueue) if ActiveSupport::IsolatedExecutionState[:job_commands_inline]

    ActiveRecord.after_all_transactions_commit { I18n.with_locale(locale, &enqueue) }
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
      pushed, error = push_inline(rows, command.fetch(:sidekiq))
      JobOutbox.where(event_id: pushed).delete_all
      { moved: pushed.size, left: total - pushed.size, error: }.compact
    end
  end

  def push_inline(rows, enqueue)
    pushed = []
    ActiveSupport::IsolatedExecutionState[:job_commands_inline] = true
    rows.each do |row|
      enqueue.call(row.payload, row.scheduled_at)
      pushed << row.event_id
    end
    [pushed, nil]
  rescue StandardError => e
    [pushed, e.class.name]
  ensure
    ActiveSupport::IsolatedExecutionState[:job_commands_inline] = nil
  end

  private_class_method :push_inline

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
