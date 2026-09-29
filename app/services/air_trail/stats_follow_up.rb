# frozen_string_literal: true

module AirTrail
  module StatsFollowUp
    module_function

    def call(payload)
      user = User.find_by(id: payload.fetch('user_id'))
      return unless user

      departures = payload.fetch('departure_epochs').map { |epoch| [nil, Time.zone.at(epoch)] }
      before = payload.fetch('months') | ImportFlights.months_for(departures, user.timezone_iana)
      ImportFlights.recalculate_stats(user.id, before | ImportFlights.new(user).affected_months)
    end
  end
end
