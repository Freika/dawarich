# frozen_string_literal: true

class BackfillKmlVelocities < ActiveRecord::Migration[8.1]
  def up
    DataMigrations::BackfillKmlVelocitiesJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue BackfillKmlVelocitiesJob: #{e.message}"
  end

  def down
    # no-op: derived speeds stay on the points
  end
end
