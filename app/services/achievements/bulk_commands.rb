# frozen_string_literal: true

module Achievements
  module BulkCommands
    KEY = 'cron:achievements_bulk_check_job'
    COMMANDS = {
      'achievements.bulk_check' => {
        version: 1,
        sidekiq: lambda { |payload, at|
          ::JobCommands.enqueue_after_commit(nil) do
            BulkCheckJob.set(wait_until: at).perform_later(**payload.symbolize_keys)
          end
        }
      }
    }.freeze
    HANDLERS = {
      'achievements.bulk_check_leaf' => {
        guard: 'Current leaf authority; replay repeats a convergent check enqueue',
        call: ->(payload) { reverse_leaf(payload) }
      }
    }.freeze

    module_function

    def root(job_id, slot)
      Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE,
                           slot ? "achievements.bulk:cron:#{slot}" : "achievements.bulk:job:#{job_id}")
    end

    def child_id(root, user_id)
      Digest::UUID.uuid_v5(root, "check:#{user_id}")
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

    def forward(options, event)
      ActiveRecord::Base.transaction do
        next false unless JobOwnership.lock_owner('command:achievements.bulk_check') == :oban

        ::JobCommands.forward('achievements.bulk_check', options.stringify_keys,
                              event_id: event, aggregate_id: nil, producer: name)
        true
      end
    end

    def schedule(user_id, options, at, event)
      if JobOwnership.lock_owner('command:achievements.check') == :oban
        payload = { 'user_id' => user_id, 'notify' => options.fetch(:notify), 'oldest_timestamp' => nil }
        ::JobCommands.forward('achievements.check', payload, event_id: child_id(event, user_id),
                              aggregate_id: user_id, producer: name, scheduled_at: at)
      else
        ::JobCommands.enqueue_after_commit(nil) do
          CheckJob.set(wait_until: at).perform_later(user_id, notify: options.fetch(:notify),
                                                           force: options.fetch(:force))
        end
      end
    end

    def reverse_leaf(payload)
      user_id = payload.fetch('user_id')
      return unless User.exists?(id: user_id)

      at = Time.iso8601(payload.fetch('run_at'))
      ActiveRecord::Base.transaction do
        if JobOwnership.lock_owner('command:achievements.check') == :oban
          data = { 'user_id' => user_id, 'notify' => payload.fetch('notify'), 'oldest_timestamp' => nil }
          ::JobCommands.forward('achievements.check', data, event_id: payload.fetch('event_id'),
                                aggregate_id: user_id, producer: name, scheduled_at: at)
        else
          ::JobCommands.enqueue_after_commit(nil) do
            CheckJob.set(wait_until: at).perform_later(user_id, notify: payload.fetch('notify'), force: false)
          end
        end
      end
    end
  end
end
