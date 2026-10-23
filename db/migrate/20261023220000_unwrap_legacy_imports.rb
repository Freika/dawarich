# frozen_string_literal: true

class UnwrapLegacyImports < ActiveRecord::Migration[8.1]
  def up
    DataMigrations::UnwrapLegacyImportsJob.perform_later
  rescue StandardError => e
    Rails.logger.warn "[Migration] Could not enqueue UnwrapLegacyImportsJob: #{e.message}"
  end

  def down
    # no-op: the original names stay on the attached blobs
  end
end
