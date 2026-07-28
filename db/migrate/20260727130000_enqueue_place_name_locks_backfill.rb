# frozen_string_literal: true

class EnqueuePlaceNameLocksBackfill < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillPlaceNameLocksJob.perform_later
  end

  def down; end
end
