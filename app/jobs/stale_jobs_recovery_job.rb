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
      error_message = I18n.t('jobs.stale_jobs_recovery_job.export_timed_out_after_being_stuck_in_processing')
      export.update!(status: :failed, error_message: error_message)

      I18n.with_locale(export.user.locale) do
        Notifications::Create.new(
          user: export.user,
          kind: :error,
          title: I18n.t('jobs.stale_jobs_recovery_job.export_failed'),
          content: I18n.t('jobs.stale_jobs_recovery_job.export_name_was_stuck_in_processing_and_has_been_marked',
                          name: export.name)
        ).call
      end
    rescue StandardError => e
      Rails.logger.error("Failed to recover stale export #{export.id}: #{e.message}")
    end
  end

  def recover_stale_imports
    Import.processing.where(processing_started_at: ...IMPORT_TIMEOUT.ago).find_each do |import|
      error_message = I18n.t('jobs.stale_jobs_recovery_job.import_timed_out_after_being_stuck_in_processing')
      import.update!(status: :failed, error_message: error_message)

      I18n.with_locale(import.user.locale) do
        Notifications::Create.new(
          user: import.user,
          kind: :error,
          title: I18n.t('jobs.stale_jobs_recovery_job.import_failed'),
          content: I18n.t('jobs.stale_jobs_recovery_job.import_name_was_stuck_in_processing_and_has_been_marked',
                          name: import.name)
        ).call
      end
    rescue StandardError => e
      Rails.logger.error("Failed to recover stale import #{import.id}: #{e.message}")
    end
  end
end
