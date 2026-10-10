# frozen_string_literal: true

module Stats
  module Commands
    COMMANDS = {
      'stats.full_recalculation' => {
        version: 1,
        sidekiq: ->(payload, at) { JobCommands.enqueue_after_commit(nil) { full_recalculation(payload, at) } }
      },
      'stats.calculate_month' => {
        version: 1,
        sidekiq: ->(payload, at) { JobCommands.enqueue_after_commit(nil) { calculate(payload, at) } }
      }
    }.freeze

    HANDLERS = {
      'stats.full_recalculation' => {
        guard: 'The source job clears the shared debounce and schedules current tracked months',
        call: lambda { |payload|
          JobCommands.produce('stats.full_recalculation', payload.except('run_at'),
                              aggregate_id: payload.fetch('user_id'), producer: name,
                              scheduled_at: Time.zone.at(payload.fetch('run_at')))
        }
      },
      'stats.calculate_month' => {
        guard: 'The monthly execution receipt commits atomically with the accepted result',
        call: lambda { |payload|
          next unless User.exists?(id: payload.fetch('user_id'))

          calculate(payload, Time.zone.at(payload.fetch('run_at')))
        }
      },
      'stats.caches_invalidated' => {
        guard: 'Rails.cache deletes of the user caches; a repeat deletes nothing more',
        call: lambda { |payload|
          cache = Cache::InvalidateUserCaches.new(payload.fetch('user_id'), year: payload.fetch('year'))
          next cache.call if payload.fetch('scope') == 'all'

          cache.invalidate_countries_visited
          cache.invalidate_cities_visited
          cache.invalidate_insights_digest
        }
      }
    }.freeze

    module_function

    def full_recalculation(payload, at)
      job = Stats::FullRecalculationJob.new(payload.fetch('user_id'))
      job.job_id = payload.fetch('source_job_id')
      job.enqueue(wait_until: at)
    end

    def calculate(payload, at)
      options = { notify_on_failure: payload.fetch('notify_on_failure') }
      options[:execution_receipt] = payload['source_job_id'] if payload['source_job_id']
      job = Stats::CalculatingJob.new(
        payload.fetch('user_id'), payload.fetch('year'), payload.fetch('month'),
        **options
      )
      job.job_id = payload['source_job_id'] if payload['source_job_id']
      job.enqueue(wait_until: at)
    end
  end
end
