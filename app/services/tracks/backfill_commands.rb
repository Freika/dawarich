# frozen_string_literal: true

module Tracks::BackfillCommands
  COMMANDS = {
    'tracks.throttled_backfill' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          Time.use_zone(payload.fetch('time_zone')) do
            Tracks::ThrottledBackfillJob.set(wait_until: at).perform_later(payload.fetch('user_id'),
                                                                           payload.fetch('cursor_timestamp'),
                                                                           walk_id: payload.fetch('walk_id'),
                                                                           time_zone: payload.fetch('time_zone'))
          end
        end
      }
    },
    'tracks.backfill' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          Time.use_zone(payload.fetch('time_zone')) do
            Tracks::BackfillGenerationJob.set(wait_until: at).perform_later(payload.fetch('user_id'),
                                                                            cycle_id: payload.fetch('cycle_id'),
                                                                            time_zone: payload.fetch('time_zone'))
          end
        end
      }
    }
  }.freeze

  module_function

  def execute_range(user_id, event_id, cycle_id: nil, time_zone: nil)
    range = nil
    ActiveRecord::Base.transaction do
      owner = JobOwnership.lock_owner('command:tracks.backfill')
      JobOwnership.lock_owner(Tracks::GenerationCommand::OWNER_KEY) if owner == :sidekiq
      next if done?(event_id)

      range = Tracks::BackfillState.for_execution(user_id, cycle_id:, time_zone:)
      next unless range

      cycle = range.fetch('cycle_id')
      if owner == :oban
        JobCommands.forward('tracks.backfill', range.slice('user_id', 'cycle_id', 'time_zone'),
                            event_id: cycle, aggregate_id: user_id, producer: name)
        claim(event_id) unless event_id == cycle
      elsif !JobOutbox.exists?(event_id: cycle, command_type: 'tracks.backfill') && claim(cycle)
        claim(event_id) unless event_id == cycle
        publish_range(range)
        connection.execute(sql('DELETE FROM phoenix.track_backfill_ranges WHERE user_id = ? AND cycle_id = ?::uuid',
                               user_id, cycle))
      end
    end
  rescue StandardError => e
    Tracks::BackfillState.rearm(range) if range
    ExceptionReporter.call(e, "Failed to schedule backfill track generation for user #{user_id}")
  end

  def forward_walk(user_id, cursor, event_id, walk_id: nil, time_zone: nil)
    ActiveRecord::Base.transaction do
      owner = JobOwnership.lock_owner('command:tracks.throttled_backfill')
      next true if done?(event_id)
      next false unless owner == :oban

      Tracks::ThrottledBackfillState.new(user_id, cursor, walk_id:, time_zone:).forward(event_id)
      claim(event_id)
      true
    end
  end

  def reverse_walk(payload)
    if payload['walk_id']
      at = Time.iso8601(payload.fetch('scheduled_at'))
      JobCommands.enqueue_after_commit(nil) do
        Time.use_zone(payload.fetch('time_zone')) do
          Tracks::ThrottledBackfillJob.set(wait_until: at).perform_later(payload.fetch('user_id'),
                                                                         payload.fetch('cursor_timestamp'),
                                                                         walk_id: payload.fetch('walk_id'),
                                                                         time_zone: payload.fetch('time_zone'))
        end
      end
    else
      user = User.find_by(id: payload.fetch('user_id'))
      Tracks::ThrottledBackfillJob.schedule(user) if user
    end
  end

  def publish_range(range)
    Time.use_zone(range.fetch('time_zone')) do
      start_at = Time.zone.at(range.fetch('earliest_timestamp')).beginning_of_day
      end_at = [Time.zone.at(range.fetch('latest_timestamp')).end_of_day, 6.hours.ago].min
      if JobOwnership.lock_owner(Tracks::GenerationCommand::OWNER_KEY) == :oban
        payload = Tracks::GenerationCommand.payload(range.fetch('user_id'), start_at:, end_at:, mode: :bulk,
                                                                          untracked_only: true, import_id: nil,
                                                                          job_queue: nil)
        Tracks::GenerationCommand.forward(payload, event_id: range.fetch('cycle_id'), producer: name)
      else
        ActiveRecord.after_all_transactions_commit do
          Time.use_zone(range.fetch('time_zone')) do
            Tracks::ParallelGeneratorJob.perform_later(range.fetch('user_id'), start_at:, end_at:, mode: :bulk,
                                                                             untracked_only: true)
          end
        end
      end
    end
  end

  def connection = ActiveRecord::Base.connection
  def sql(statement, *binds) = ActiveRecord::Base.sanitize_sql_array([statement, *binds])

  def done?(event_id)
    connection.select_value(sql('SELECT 1 FROM phoenix.processed_commands WHERE event_id = ?::uuid', event_id)).present?
  end

  def claim(event_id)
    connection.select_value(sql('INSERT INTO phoenix.processed_commands (event_id, handler, processed_at) ' \
                                'VALUES (?::uuid, ?, ?) ON CONFLICT (event_id) DO NOTHING RETURNING event_id',
                                event_id, name, Time.current))
  end

  private_class_method :publish_range, :connection, :sql, :done?, :claim
end
