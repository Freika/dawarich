# frozen_string_literal: true

module Stats
  module Commands
    COMMANDS = {
      'stats.calculate_month' => {
        version: 1,
        sidekiq: ->(payload, at) { JobCommands.enqueue_after_commit(nil) { calculate(payload, at) } }
      }
    }.freeze

    HANDLERS = {
      'stats.calculate_month' => {
        guard: 'Stats::CalculatingJob recomputes the month from current points and flights under stat.lock!; ' \
               'a repeat costs one more convergent calculation',
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

    def calculate(payload, at)
      Stats::CalculatingJob.set(wait_until: at).perform_later(
        payload.fetch('user_id'), payload.fetch('year'), payload.fetch('month'),
        notify_on_failure: payload.fetch('notify_on_failure')
      )
    end
  end
end
