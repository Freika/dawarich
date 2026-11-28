# frozen_string_literal: true

class EnqueueUntrackedPointsReattachment < ActiveRecord::Migration[8.1]
  def up
    DataMigrations::ReattachUntrackedPointsJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=ReattachUntrackedPointsJob enqueued=false error=#{e.message}"
  end

  def down; end
end
