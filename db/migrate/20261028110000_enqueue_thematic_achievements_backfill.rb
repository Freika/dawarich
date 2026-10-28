# frozen_string_literal: true

# Existing dwell already knows which countries were visited. A silent check
# awards the new sets without rebuilding history or presenting an import deck.
class EnqueueThematicAchievementsBackfill < ActiveRecord::Migration[8.1]
  def up
    Achievements::BulkCheckJob.perform_later(notify: false, force: true)
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=ThematicAchievementsBackfill enqueued=false error=#{e.message}"
  end

  def down; end
end
