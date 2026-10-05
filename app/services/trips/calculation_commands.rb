# frozen_string_literal: true

module Trips
  module CalculationCommands
    HANDLERS = {
      'trips.calculate' => {
        guard: 'Owned trip lookup and the canonical calculation command deduplicate pending native work.',
        call: lambda { |payload|
          JobCommands.enqueue_after_commit(nil) do
            trip = Trip.find_by(id: payload.fetch('trip_id'), user_id: payload.fetch('user_id'))
            trip&.enqueue_calculation_jobs(payload.fetch('distance_unit'))
          end
        }
      }
    }.freeze
  end
end
