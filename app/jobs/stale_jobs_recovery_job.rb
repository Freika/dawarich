# frozen_string_literal: true

class StaleJobsRecoveryJob < ApplicationJob
  queue_as :exports
  sidekiq_options retry: false

  EXPORT_TIMEOUT = 2.hours
  IMPORT_TIMEOUT = 6.hours

  def perform
    Imports::ExtractionMonitor.new.call
  ensure
    JobOwnership.with_owner('cron:stale_jobs_recovery_job') do
      recover_stale_exports
      recover_stale_imports
    end
  end

  private

  def recover_stale_exports
    Export.processing.where(processing_started_at: ...EXPORT_TIMEOUT.ago).find_each do |export|
      I18n.with_locale(export.user.locale) do
        error_message = I18n.t('jobs.stale_jobs_recovery_job.export_timed_out_after_being_stuck_in_processing')
        next unless Export.where(id: export.id, status: :processing)
                          .update_all(status: :failed, error_message:, updated_at: Time.current) == 1

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
      Imports::StaleImportRecovery.call(import, IMPORT_TIMEOUT.ago)
    rescue StandardError => e
      Rails.logger.error("Failed to recover stale import #{import.id}: #{e.message}")
    end
  end
end
