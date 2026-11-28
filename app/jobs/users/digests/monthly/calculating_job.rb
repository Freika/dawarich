# frozen_string_literal: true

class Users::Digests::Monthly::CalculatingJob < ApplicationJob
  queue_as :digests

  def perform(user_id, year, month)
    user = find_user_or_skip(user_id) || return

    I18n.with_locale(user.locale) do
      Stats::CalculateMonth.new(user_id, year, month, notify_on_failure: false).call
      Users::Digests::CalculateMonth.new(user_id, year, month).call

      Users::Digests::Monthly::EmailSendingJob.perform_later(user_id, year, month)
    end
  rescue StandardError => e
    log_failure("Monthly digest calculation failed for user #{user_id}", e)
    ExceptionReporter.call(e, "Monthly digest calculation failed for user #{user_id}")
    create_digest_failed_notification(user_id, e)
  end

  private

  BACKTRACE_LINE_LIMIT = 20

  # The rescue swallows the error and ExceptionReporter is silent on
  # self-hosted, so the trace goes to the log for whoever runs the instance.
  def log_failure(message, error)
    trace = error.backtrace&.first(BACKTRACE_LINE_LIMIT)&.join("\n")
    Rails.logger.error("#{message}: #{error.class}: #{error.message}\n#{trace}")
  end

  def create_digest_failed_notification(user_id, error)
    user = find_user_or_skip(user_id) || return

    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('jobs.users.digests.monthly.calculating_job.monthly_digest_calculation_failed'),
        content: error.message,
        operator_only: true
      ).call
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
