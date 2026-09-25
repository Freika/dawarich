# frozen_string_literal: true

# Retired with the points v2 rewrite: the per-tracker recalculation and the
# tracker-id backfillers it drove read legacy points columns that no longer
# exist, and every install that could benefit ran it long ago. The class
# stays as a no-op because migrations 20260514120100, 20260719190000 and
# 20260730160000 enqueue it by name at migrate time.
class DataMigrations::RecalculatePerTrackerTracksJob < ApplicationJob
  queue_as :data_migrations

  def perform(*)
    Rails.logger.info('[RecalculatePerTrackerTracks] retired no-op (points v2)')
  end
end
