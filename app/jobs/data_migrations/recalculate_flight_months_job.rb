# frozen_string_literal: true

class DataMigrations::RecalculateFlightMonthsJob < ApplicationJob
  queue_as :data_migrations

  def perform
    User.where(id: Flight.select(:user_id)).find_each do |user|
      jobs = user.flights.stat_months(user.timezone_iana).map do |year, month|
        Stats::CalculatingJob.new(user.id, year, month)
      end
      ActiveJob.perform_all_later(jobs)
    end
  end
end
