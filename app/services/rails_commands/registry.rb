# frozen_string_literal: true

module RailsCommands
  module Registry
    HANDLERS = {
      'visit_months_changed' => {
        guard: 'Rails.cache.delete of the month-summary keys; a repeat deletes nothing more',
        call: lambda { |payload|
          user = User.find_by(id: payload.fetch('user_id'))
          next unless user

          times = payload.fetch('started_at').map { Time.iso8601(_1) }
          Visits::Detection::MachineVisitWipe.bust_month_caches(user, times)
        }
      },
      'airtrail_stats' => {
        guard: 'Converges: each Stats::CalculatingJob recomputes its month from current points and flights ' \
               'under stat.lock!, so a repeat enqueues the same months again; the cost is one more recalculation ' \
               'and cache invalidation per month, which every Rails AirTrail sync already pays',
        call: ->(payload) { AirTrail::StatsFollowUp.call(payload) }
      }
    }.merge(Points::ArrivalCommands::HANDLERS).freeze

    module_function

    def handler(kind) = HANDLERS.dig(kind, :call)
  end
end
