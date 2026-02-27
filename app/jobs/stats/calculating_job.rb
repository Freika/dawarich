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
    user = User.find_by(id: user_id)
    unless user
      Rails.logger.info "#{self.class.name}: User #{user_id} not found, skipping"
      return
    end

    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Stats update failed',
      content: "#{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  end
end
