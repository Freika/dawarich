# frozen_string_literal: true

class Import::UpdatePointsCountJob < ApplicationJob
  queue_as :imports
  self.enqueue_after_transaction_commit = true

  def perform(import_id)
    import = Import.find_by(id: import_id)
    return unless import

    count = import.points.count
    result = JobOwnership.with_owner(ImportCommands::UPDATE_POINTS_COUNT_KEY) { import.update(processed: count) }
    ImportCommands.forward_update_points_count(import_id, event_id: job_id) if result == :not_owner
  end
end
