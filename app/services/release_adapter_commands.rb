# frozen_string_literal: true

module ReleaseAdapterCommands
  COMMANDS = {
    'release.achievements_backfill' => {
      version: 1, sidekiq: ->(_payload, at) { ReleaseCommands.later(DataMigrations::BackfillAchievementsJob, at) }
    },
    'release.import_backfill' => {
      version: 1,
      sidekiq: lambda { |payload, at|
        JobCommands.enqueue_after_commit(nil) do
          Time.use_zone(payload.fetch('ambient_zone')) do
            TransportationModes::ImportBackfillJob.set(wait_until: at).perform_later(payload.fetch('import_id'))
          end
        end
      }
    }
  }.freeze

  module_function

  def reverse_bulk(payload)
    JobCommands.enqueue_after_commit(nil) do
      job = Achievements::BulkCheckJob.new(**payload.fetch('options').symbolize_keys)
      job.job_id = payload.fetch('job_id')
      job.enqueue(wait_until: Time.iso8601(payload.fetch('run_at'))) || raise('Achievements enqueue aborted')
    end
  end
end
