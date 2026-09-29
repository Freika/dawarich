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
      }
    }.freeze

    module_function

    def handler(kind) = HANDLERS.dig(kind, :call)
  end
end
