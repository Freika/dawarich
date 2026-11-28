# frozen_string_literal: true

# Earlier backfill jobs returned immediately on self-hosted instances where
# achievements were still behind a disabled flag. Re-enqueue after rollout;
# the job checks only users without current progress and suppresses alerts.
class EnqueueUngatedAchievementsBackfill < ActiveRecord::Migration[8.1]
  def up
    DataMigrations::BackfillAchievementsJob.perform_later
  rescue NameError
    raise
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=BackfillAchievementsJob enqueued=false error=#{e.message}"
  end

  def down; end
end
