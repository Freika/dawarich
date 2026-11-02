# frozen_string_literal: true

# Existing dwell already knows which countries were visited. A silent check
# awards the new sets without rebuilding history or presenting an import deck.
class EnqueueThematicAchievementsBackfill < ActiveRecord::Migration[8.1]
  ENQUEUED_KEY = 'thematic_achievements_backfill_enqueued'

  def up
    connection.transaction do
      connection.execute('SELECT pg_advisory_xact_lock(20261028110000)')
      metadata = connection.pool.internal_metadata
      next if metadata[ENQUEUED_KEY] == 'true'

      job = Achievements::BulkCheckJob.perform_later(notify: false, force: true)
      metadata[ENQUEUED_KEY] = 'true' if job&.successfully_enqueued?
    end
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=ThematicAchievementsBackfill enqueued=false error=#{e.message}"
  end

  def down; end
end
