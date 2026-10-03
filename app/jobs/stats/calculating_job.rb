# frozen_string_literal: true

class Stats::CalculatingJob < ApplicationJob
  queue_as :stats
  OWNER_KEY = 'command:stats.calculate_month'

  def perform(user_id, year, month, notify_on_failure: true)
    return forward(user_id, year, month, notify_on_failure) if JobOwnership.oban?(OWNER_KEY)

    calculate(user_id, year, month, notify_on_failure)
  end

  private

  def calculate(user_id, year, month, notify_on_failure)
    user = find_user_or_skip(user_id) || return

    I18n.with_locale(user.locale) do
      Stats::CalculateMonth.new(user_id, year, month, notify_on_failure:).call
    end
  rescue StandardError => e
    Rails.logger.error("Stats::CalculatingJob failed for user #{user_id} #{year}-#{month}: #{e.class}: #{e.message}")

    create_stats_update_failed_notification(user_id, e) if notify_on_failure
  end

  def forward(user_id, year, month, notify_on_failure)
    JobCommands.forward('stats.calculate_month',
                        { 'user_id' => user_id, 'year' => year.to_i, 'month' => month.to_i,
                          'notify_on_failure' => notify_on_failure },
                        event_id: job_id, aggregate_id: user_id, producer: self.class.name)
  end

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
