# frozen_string_literal: true

class BackfillFamiliesForFamilyPlanUsers < ActiveRecord::Migration[8.0]
  def up
    DataMigrations::BackfillFamiliesForFamilyPlanJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] job=BackfillFamiliesForFamilyPlanJob enqueued=false error=#{e.message}"
  end

  def down; end
end
