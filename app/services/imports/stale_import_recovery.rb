# frozen_string_literal: true

module Imports
  module StaleImportRecovery
    module_function

    def call(import, cutoff)
      ActiveRecord::Base.transaction do
        connection = ActiveRecord::Base.connection
        name = "import:#{import.id}"
        holder = SecureRandom.uuid
        leased = PhoenixLease.table?
        next if leased && connection.exec_update(PhoenixLease::ACQUIRE, 'StaleImport',
                                                 [name, holder, PhoenixLease::TTL]) != 1

        begin
          import.lock!
          next unless import.processing? && import.processing_started_at && import.processing_started_at < cutoff
          next if active_attempt?(connection, import.id)

          fail_import(import)
        ensure
          connection.exec_update(PhoenixLease::RELEASE, 'StaleImport', [name, holder]) if leased
        end
      end
    end

    def active_attempt?(connection, id)
      return false unless PhoenixSchema.table?('import_runs') &&
                          connection.select_value("SELECT to_regclass('oban.oban_jobs') IS NOT NULL")

      connection.select_value(<<~SQL, 'StaleImport', [id]).present?
        SELECT 1 FROM phoenix.import_runs r JOIN oban.oban_jobs j ON j.id=r.job_id
        WHERE r.import_id=$1 AND j.state='executing' AND j.attempt=r.attempt
          AND j.args->>'event_id'=r.event_id::text
          AND j.args->>'import_id'=r.import_id::text AND j.args->>'user_id'=r.user_id::text
          AND j.attempted_at>statement_timestamp()-interval '55 minutes'
        LIMIT 1
      SQL
    end

    def fail_import(import)
      I18n.with_locale(import.user.locale) do
        error_message = I18n.t('jobs.stale_jobs_recovery_job.import_timed_out_after_being_stuck_in_processing')
        import.update!(status: :failed, error_message:)
        Notifications::Create.new(
          user: import.user,
          kind: :error,
          title: I18n.t('jobs.stale_jobs_recovery_job.import_failed'),
          content: I18n.t('jobs.stale_jobs_recovery_job.import_name_was_stuck_in_processing_and_has_been_marked',
                          name: import.name)
        ).call
      end
    end
  end
end
