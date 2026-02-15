# frozen_string_literal: true

class StaleJobsRecoveryJob < ApplicationJob
  queue_as :exports
  sidekiq_options retry: false

  EXPORT_TIMEOUT = 2.hours
  IMPORT_TIMEOUT = 6.hours

  def perform
    recover_stale_exports
    recover_stale_imports
  end

  private

  def recover_stale_exports
    Export.processing.where(processing_started_at: ...EXPORT_TIMEOUT.ago).find_each do |export|
      export.update!(status: :failed, error_message: 'Export timed out after being stuck in processing')

      Notifications::Create.new(
        user: export.user,
        kind: :error,
        title: 'Export failed',
        content: "Export \"#{export.name}\" was stuck in processing and has been marked as failed."
      ).call
    rescue StandardError => e
      Rails.logger.error("Failed to recover stale export #{export.id}: #{e.message}")
    end
  end

  def recover_stale_imports
    Import.processing.where(processing_started_at: ...IMPORT_TIMEOUT.ago).find_each do |import|
      import.update!(status: :failed)

      Notifications::Create.new(
        user: import.user,
        kind: :error,
        title: 'Import failed',
        content: "Import \"#{import.name}\" was stuck in processing and has been marked as failed."
      ).call
    rescue StandardError => e
      Rails.logger.error("Failed to recover stale import #{import.id}: #{e.message}")
    end
  end
end
