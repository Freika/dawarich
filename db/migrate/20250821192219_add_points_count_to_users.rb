# frozen_string_literal: true

class AddPointsCountToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :points_count, :integer, default: 0, null: false

    # Initialize counter cache for existing users using background job
    reversible do |dir|
      dir.up do
        # Tolerate the job class being renamed/removed and Sidekiq being down.

        DataMigrations::PrefillPointsCounterCacheJob.perform_later
      rescue StandardError => e
        Rails.logger.warn "[Migration] Could not enqueue PrefillPointsCounterCacheJob: #{e.message}"
      end
    end
  end
end
