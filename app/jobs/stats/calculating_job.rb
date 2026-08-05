# frozen_string_literal: true

class Stats::CalculatingJob < ApplicationJob
  queue_as :stats

  def perform(user_id, year, month)
    Stats::CalculateMonth.new(user_id, year, month).call
  rescue StandardError => e
    create_stats_update_failed_notification(user_id, e)
  end

  private

  def create_stats_update_failed_notification(user_id, error)
    user = find_user_or_skip(user_id) || return

    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('jobs.stats.calculating_job.stats_update_failed'),
        content: I18n.t('jobs.stats.calculating_job.message_stacktrace_n', message: error.message,
                        backtrace: error.backtrace.join("\n"))
      ).call
    end
  end
end
