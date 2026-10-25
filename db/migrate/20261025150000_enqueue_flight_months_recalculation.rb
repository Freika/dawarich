# frozen_string_literal: true

class EnqueueFlightMonthsRecalculation < ActiveRecord::Migration[8.1]
  def up
    DataMigrations::RecalculateFlightMonthsJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=RecalculateFlightMonthsJob enqueued=false error=#{e.message}"
  end

  def down; end
end
