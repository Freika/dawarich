# frozen_string_literal: true

class Stats::CalculatingJob < ApplicationJob
  queue_as :stats

  def perform(user_id, year, month)
    Stats::CalculateMonth.new(user_id, year, month).call

    create_stats_updated_notification(user_id, year, month)
  rescue StandardError => e
    create_stats_update_failed_notification(user_id, e)
  end

  private

  def create_stats_updated_notification(user_id, year, month)
    user = User.find(user_id)

    Notifications::Create.new(
      user:,
      kind: :info,
      title: "Stats updated: #{year}-#{month}",
      content: "Stats updated for #{year}-#{month}"
    ).call
  end

  def create_stats_update_failed_notification(user_id, error)
    user = User.find(user_id)

    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Stats update failed',
      content: "#{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  end
end
