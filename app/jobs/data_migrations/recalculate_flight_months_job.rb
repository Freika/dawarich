# frozen_string_literal: true

class DataMigrations::RecalculateFlightMonthsJob < ApplicationJob
  queue_as :data_migrations

  def perform
    user_ids = User.where(id: Flight.select(:user_id)).pluck(:id)
    ActiveJob.perform_all_later(user_ids.map { |user_id| DataMigrations::RecalculateUserFlightMonthsJob.new(user_id) })
  end
end
