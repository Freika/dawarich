# frozen_string_literal: true

class Users::Digests::Yearly::CalculatingJob < ApplicationJob
  queue_as :digests

  def perform(user_id, year)
    recalculate_monthly_stats(user_id, year)
    Users::Digests::CalculateYear.new(user_id, year).call

    Users::Digests::Yearly::EmailSendingJob.perform_later(user_id, year)
  rescue StandardError => e
    create_digest_failed_notification(user_id, e, 'Year-End Digest')
  end

  private

  def recalculate_monthly_stats(user_id, year)
    (1..12).each do |month|
      Stats::CalculateMonth.new(user_id, year, month).call
    end
  end

  def create_digest_failed_notification(user_id, error, period_label)
    user = find_user_or_skip(user_id) || return

    Notifications::Create.new(
      user:,
      kind: :error,
      title: "#{period_label} calculation failed",
      content: "#{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
