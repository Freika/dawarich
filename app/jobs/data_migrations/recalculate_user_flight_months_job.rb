# frozen_string_literal: true

class DataMigrations::RecalculateUserFlightMonthsJob < ApplicationJob
  queue_as :stats

  def perform(user_id)
    user = find_user_or_skip(user_id) || return

    Stats::RecalculateMonths.new(user, user.flights.stat_months(user.timezone_iana)).call
  end
end
