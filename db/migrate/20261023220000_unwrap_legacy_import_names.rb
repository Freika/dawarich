# frozen_string_literal: true

class UnwrapLegacyImportNames < ActiveRecord::Migration[8.1]
  def up
    DataMigrations::UnwrapLegacyImportNamesJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue UnwrapLegacyImportNamesJob: #{e.message}"
  end

  def down
    # no-op: the original names stay on the attached blobs
  end
end
