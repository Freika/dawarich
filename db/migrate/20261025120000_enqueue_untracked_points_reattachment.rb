# frozen_string_literal: true

class EnqueueUntrackedPointsReattachment < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::ReattachUntrackedPointsJob.perform_later
  end

  def down; end
end
