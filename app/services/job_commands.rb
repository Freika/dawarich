# frozen_string_literal: true

module JobCommands
  COMMANDS = {
    'imports.prepare_download' => {
      version: 1,
      sidekiq: lambda { |payload, _at|
        JobCommands.enqueue_after_commit(nil) do
          Imports::PrepareDownloadJob.perform_later(payload.fetch('import_id'), payload.fetch('source_blob_id'),
                                                    expected_user_id: payload.fetch('user_id'))
        end
      }
    },
    'imports.destroy' => {
      version: 1,
      sidekiq: lambda { |payload, _at|
        JobCommands.enqueue_after_commit(nil) do
          Imports::DestroyJob.perform_later(payload.fetch('import_id'), expected_user_id: payload.fetch('user_id'))
        end
      }
    },
    'imports.process_gpx' => {
      version: 1,
      sidekiq: lambda { |payload, _at|
        JobCommands.enqueue_after_commit(nil) do
          Time.use_zone(payload.fetch('time_zone')) do
            Import::ProcessJob.perform_later(payload.fetch('import_id'))
          end
        end
      }
    },
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
      sidekiq: lambda { |payload, _at|
        JobCommands.enqueue_after_commit(nil) { Import::UpdatePointsCountJob.perform_later(payload['import_id']) }
      }
    },
    'imports.airtrail_flights' => {
      version: 1,
      sidekiq: lambda { |payload, _at|
        JobCommands.enqueue_after_commit(nil) { AirTrail::ImportFlightsJob.perform_later(payload['user_id']) }
      }
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
    'tracks.generate_range' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          Tracks::ParallelGeneratorJob.set(wait_until: at)
                                      .perform_later(payload.fetch('user_id'),
                                                     **Tracks::GenerationCommand.job_options(payload))
        end
      }
    },
    'tracks.generate_realtime' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          Tracks::RealtimeGenerationJob.set(wait_until: at).perform_later(payload.fetch('user_id'))
        end
      }
    },
    'tracks.recalculate' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          Tracks::RecalculateJob.set(wait_until: at).perform_later(payload.fetch('track_id'))
        end
      }
    },
    'transportation.reclassify_track' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          TransportationModes::ReclassifyTrackJob.set(wait_until: at).perform_later(
            payload.fetch('track_id'), report_progress: payload.fetch('report_progress'), user_id: payload['user_id']
          )
        end
      }
    },
    'exports.points' => {
      version: 2,
      rehome_versions: [1, 2],
      sidekiq: lambda { |payload, _at|
        JobCommands.enqueue_after_commit(nil) do
          Time.use_zone(payload.fetch('time_zone', Time.zone)) do
            ExportJob.perform_later(payload.fetch('export_id'))
          end
        end
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
    **UserMailCommands::TYPES.to_h do |email_type, type|
      [type, { version: 1, sidekiq: UserMailCommands.legacy(email_type) }]
    end,
    'geocoding.reverse_point' => {
      version: 1,
      sidekiq: lambda { |payload, _at|
        JobCommands.enqueue_after_commit(nil) do
          force = payload.fetch('force')
          jobs = payload.fetch('point_ids').map { |id| ReverseGeocodingJob.new('Point', id, force:) }
          ActiveJob.perform_all_later(jobs)
        end
      }
    },
    'geocoding.reverse_place' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          ReverseGeocodingJob.set(wait_until: at).perform_later('place', payload.fetch('place_id'))
        end
      }
    },
    'visits.suggest' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          VisitSuggestingJob.set(wait_until: at).perform_later(**Visits::Commands.job_arguments(payload))
        end
      }
    },
    'visits.full_history_redetect' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          Visits::FullHistoryRedetectJob.set(wait_until: at).perform_later(payload.fetch('user_id'))
        end
      }
    },
    'enhanced_import.extract_gpx' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          EnhancedImport::ExtractJob.set(wait_until: at).perform_later(payload.fetch('import_id'),
                                                                       attempt: payload.fetch('lock_attempt'))
        end
      }
    },
    'enhanced_import.destroy_gpx' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          EnhancedImport::DestroyJob.set(wait_until: at).perform_later(payload.fetch('import_id'))
        end
      }
    }
  }.merge(ReleaseCommands::COMMANDS)
   .merge(Tracks::BackfillCommands::COMMANDS)
   .merge(Families::JobCommands::COMMANDS)
   .merge(Stats::Commands::COMMANDS)
   .merge(Imports::ProcessCommands::COMMANDS)
   .merge(Posters::CreationCommand::COMMANDS)
   .merge(Users::Digests::Commands::COMMANDS).freeze

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
    payload = payload.merge('time_zone' => payload.fetch('time_zone', Time.zone.name)) if type == 'exports.points'

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
      versions = command.fetch(:rehome_versions, command.fetch(:version))
      pending = JobOutbox.pending.where(command_type: type, command_version: versions)
      total = pending.count
      rows = pending.lock('FOR UPDATE SKIP LOCKED').to_a
      pushed, error = push_inline(rows, command.fetch(:sidekiq))
      JobOutbox.where(event_id: pushed).delete_all
      result = { moved: pushed.size, left: total - pushed.size, error: }.compact
      if type == 'tracks.recalculate'
        aliases = Points::AnomalyFilterCommands.rehome_pending!(by:)
        result = { moved: result[:moved] + aliases[:moved], left: result[:left] + aliases[:left],
                   error: result[:error] || aliases[:error] }.compact
      end
      result
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
