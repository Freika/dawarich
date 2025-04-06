# frozen_string_literal: true

class Import::UpdatePointsCountJob < ApplicationJob
  queue_as :imports

  def perform(import_id)
    import = Import.find(import_id)

    import.update(processed: import.points.count)
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
