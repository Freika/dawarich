# frozen_string_literal: true

class FixRouteOpacityDefault < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::FixRouteOpacityJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue FixRouteOpacityJob: #{e.message}"
  end

  def down
    # no-op: reverting would reintroduce the bug
  end
end
