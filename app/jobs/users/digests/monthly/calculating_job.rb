# frozen_string_literal: true

class Users::Digests::Monthly::CalculatingJob < ApplicationJob
  queue_as :digests
  OWNER_KEY = 'command:digests.calculate_month'

  def perform(user_id, year, month)
    return forward(user_id, year, month) if JobOwnership.oban?(OWNER_KEY)

    calculate(user_id, year, month)
  end

  private

  def calculate(user_id, year, month)
    user = find_user_or_skip(user_id) || return

    I18n.with_locale(user.locale) do
      Stats::CalculateMonth.new(user_id, year, month).call
      Users::Digests::CalculateMonth.new(user_id, year, month).call

      Users::Digests::Monthly::EmailSendingJob.perform_later(user_id, year, month)
    end
  rescue StandardError => e
    create_digest_failed_notification(user_id, e)
  end

  def forward(user_id, year, month)
    JobCommands.forward('digests.calculate_month',
                        { 'user_id' => user_id, 'year' => year.to_i, 'month' => month.to_i,
                          'time_zone' => Time.zone.name },
                        event_id: job_id, aggregate_id: user_id, producer: self.class.name)
  end

  BACKTRACE_LINE_LIMIT = 20

  def create_digest_failed_notification(user_id, error)
    user = find_user_or_skip(user_id) || return

    backtrace = error.backtrace&.first(BACKTRACE_LINE_LIMIT)&.join("\n")

    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('jobs.users.digests.monthly.calculating_job.monthly_digest_calculation_failed'),
        content: I18n.t('jobs.users.digests.monthly.calculating_job.message_stacktrace_backtrace',
                        message: error.message, backtrace: backtrace)
      ).call
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
