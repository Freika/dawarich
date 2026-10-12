# frozen_string_literal: true

class EnqueueNullIslandCleanup < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::CleanupNullIslandJob.perform_later
  end

  def down; end
end
