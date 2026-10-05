# frozen_string_literal: true

module Visits
  module BulkCommands
    KEY = 'cron:visit_suggesting_job'
    COMMANDS = {
      'visits.bulk_suggest' => {
        version: 1,
        sidekiq: ->(payload, at) { JobCommands.enqueue_after_commit(nil) { enqueue_bulk(payload, at) } }
      }
    }.freeze
    HANDLERS = {
      'visits.suggest' => {
        guard: 'Current leaf owner and stable child UUID preserve accepted suggestion work across hand-back',
        call: ->(payload) { reverse_leaf(payload) }
      }
    }.freeze

    module_function

    def root(job_id, slot)
      slot ? Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, "visits.bulk:cron:#{slot}") : job_id
    end

    def child_id(root, user_id, index)
      Digest::UUID.uuid_v5(root, "suggest:#{user_id}:#{index}")
    end

    def claim(root, user_id)
      return true unless PhoenixSchema.table?('processed_commands')

      event = Digest::UUID.uuid_v5(root, "scheduled:#{user_id}")
      sql = 'INSERT INTO phoenix.processed_commands(event_id,handler,processed_at) ' \
            'VALUES(?::uuid,?,?) ON CONFLICT(event_id) DO NOTHING RETURNING event_id'
      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array([sql, event, name, Time.current])
      ).present?
    end

    def forward(start_at, end_at, user_ids, job_id)
      return false unless user_ids.all? { _1.is_a?(Integer) && _1.positive? }

      ActiveRecord::Base.transaction do
        next false unless JobOwnership.lock_owner('command:visits.bulk_suggest') == :oban

        payload = { 'start_at' => start_at.iso8601(9), 'end_at' => end_at.iso8601(9), 'user_ids' => user_ids,
                    'time_zone' => Time.zone.tzinfo.name, 'source_job_id' => job_id }
        JobCommands.forward('visits.bulk_suggest', payload, event_id: job_id, aggregate_id: nil, producer: name)
        true
      end
    end

    def enqueue_bulk(payload, at)
      Time.use_zone(payload.fetch('time_zone')) do
        job = BulkVisitsSuggestingJob.new(start_at: DateTime.iso8601(payload.fetch('start_at')),
                                          end_at: DateTime.iso8601(payload.fetch('end_at')),
                                          user_ids: payload.fetch('user_ids'))
        job.job_id = payload.fetch('source_job_id')
        job.enqueue(wait_until: at) || raise('Bulk visits enqueue aborted')
      end
    end

    def schedule(user, chunks, root)
      return unless claim(root, user.id)

      owner = JobOwnership.lock_owner('command:visits.suggest')
      chunks.each_with_index do |chunk, index|
        if owner == :oban
          zone = ActiveSupport::TimeZone[user.timezone] || ActiveSupport::TimeZone[ENV.fetch('TIME_ZONE', 'UTC')]
          Time.use_zone(zone) do
            Visits::Commands.forward_suggest(user, chunk.first, chunk.last,
                                             event_id: child_id(root, user.id, index))
          end
        else
          VisitSuggestingJob.perform_later(user_id: user.id, start_at: chunk.first, end_at: chunk.last)
        end
      end
    end

    def enqueue_suggest(payload, at)
      JobCommands.enqueue_after_commit(nil) do
        job = VisitSuggestingJob.new(**Visits::Commands.job_arguments(payload))
        job.job_id = payload.fetch('event_id') if payload.key?('event_id')
        job.enqueue(wait_until: at) || raise('Visit suggestion enqueue aborted')
      end
    end

    def reverse_leaf(payload)
      return unless User.exists?(id: payload.fetch('user_id'))

      ActiveRecord::Base.transaction do
        if JobOwnership.lock_owner('command:visits.suggest') == :oban
          JobCommands.forward('visits.suggest', payload.except('event_id'), event_id: payload.fetch('event_id'),
                              aggregate_id: payload.fetch('user_id'), producer: name)
        else
          enqueue_suggest(payload, Time.current)
        end
      end
    end
  end
end
