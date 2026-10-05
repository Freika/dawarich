# frozen_string_literal: true

class StaleJobsRecoveryJob < ApplicationJob
  queue_as :exports
  sidekiq_options retry: false

  EXPORT_TIMEOUT = 2.hours
  IMPORT_TIMEOUT = 6.hours

  def perform
    Imports::ExtractionMonitor.new.call
  ensure
    recover_stale_exports
    recover_stale_imports
  end

  private

  def recover_stale_exports
    Export.processing.where(processing_started_at: ...EXPORT_TIMEOUT.ago).find_each do |export|
      result = JobOwnership.with_owner('cron:stale_jobs_recovery_job') do
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
      end
      break if result == :not_owner
    rescue StandardError => e
      Rails.logger.error("Failed to recover stale export #{export.id}: #{e.message}")
    end
  end

  def recover_stale_imports
    Import.processing.where(processing_started_at: ...IMPORT_TIMEOUT.ago).find_each do |import|
      result = JobOwnership.with_owner('cron:stale_jobs_recovery_job') do
        Imports::StaleImportRecovery.call(import, IMPORT_TIMEOUT.ago)
      end
      break if result == :not_owner
    rescue StandardError => e
      Rails.logger.error("Failed to recover stale import #{import.id}: #{e.message}")
    end
  end
end
