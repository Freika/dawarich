# frozen_string_literal: true

class Users::Digests::Yearly::CalculatingJob < ApplicationJob
  queue_as :digests

  def perform(user_id, year)
    user = find_user_or_skip(user_id) || return

    I18n.with_locale(user.locale) do
      return unless calculate_digest(user, year)

      enqueue_digest_email(user_id, year)
    end
  end

  private

  def calculate_digest(user, year)
    digest = Users::Digest.for_year_generation(user, year)
    recalculate_monthly_stats(user.id, year)
    Users::Digests::CalculateYear.new(user.id, year).call
    digest.reload.update!(generation_status: :ready)
    true
  rescue StandardError => e
    digest&.update(generation_status: :failed)
    log_failure("Yearly digest calculation failed for user #{user.id}", e)
    ExceptionReporter.call(e, "Yearly digest calculation failed for user #{user.id}")
    create_digest_failed_notification(user.id, e)
    false
  end

  def enqueue_digest_email(user_id, year)
    Users::Digests::Yearly::EmailSendingJob.perform_later(user_id, year)
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to enqueue yearly digest email')
  end

  def recalculate_monthly_stats(user_id, year)
    (1..12).each do |month|
      Stats::CalculateMonth.new(user_id, year, month, notify_on_failure: false).call
    end
  end

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
      period_label = I18n.t('jobs.users.digests.yearly.calculating_job.year_end_digest')
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('jobs.users.digests.yearly.calculating_job.period_label_calculation_failed', period_label:),
        content: error.message,
        operator_only: true
      ).call
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
