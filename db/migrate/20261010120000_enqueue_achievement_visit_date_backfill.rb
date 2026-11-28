# frozen_string_literal: true

class EnqueueAchievementVisitDateBackfill < ActiveRecord::Migration[8.1]
  # The full recalculation that restores historical visit dates now runs once
  # from LoadDisputedAreas, which ships in the same release.
  def up; end

  def down; end
end
