# frozen_string_literal: true

class Users::Digests::Yearly::CalculatingJob < ApplicationJob
  queue_as :digests

  def perform(user_id, year)
    user = find_user_or_skip(user_id) || return

    I18n.with_locale(user.locale) do
      recalculate_monthly_stats(user_id, year)
      Users::Digests::CalculateYear.new(user_id, year).call

      Users::Digests::Yearly::EmailSendingJob.perform_later(user_id, year)
    end
  rescue StandardError => e
    create_digest_failed_notification(user_id, e)
  end

  private

  def recalculate_monthly_stats(user_id, year)
    (1..12).each do |month|
      Stats::CalculateMonth.new(user_id, year, month).call
    end
  end

  BACKTRACE_LINE_LIMIT = 20

  def create_digest_failed_notification(user_id, error)
    user = find_user_or_skip(user_id) || return

    backtrace = error.backtrace&.first(BACKTRACE_LINE_LIMIT)&.join("\n")

    I18n.with_locale(user.locale) do
      period_label = I18n.t('jobs.users.digests.yearly.calculating_job.year_end_digest')
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('jobs.users.digests.yearly.calculating_job.period_label_calculation_failed', period_label:),
        content: I18n.t('jobs.users.digests.yearly.calculating_job.message_stacktrace_backtrace',
                        message: error.message, backtrace: backtrace)
      ).call
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
