# frozen_string_literal: true

class EnqueueAreasIntoPlacesBackfill < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillAreasIntoPlacesJob.perform_later
  end

  def down; end
end
