# frozen_string_literal: true

class Users::Digests::Monthly::CalculatingJob < ApplicationJob
  queue_as :digests

  def perform(user_id, year, month)
    Stats::CalculateMonth.new(user_id, year, month).call
    Users::Digests::CalculateMonth.new(user_id, year, month).call

    Users::Digests::Monthly::EmailSendingJob.perform_later(user_id, year, month)
  rescue StandardError => e
    create_digest_failed_notification(user_id, e)
  end

  private

  BACKTRACE_LINE_LIMIT = 20

  def create_digest_failed_notification(user_id, error)
    user = find_user_or_skip(user_id) || return

    backtrace = error.backtrace&.first(BACKTRACE_LINE_LIMIT)&.join("\n")

    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Monthly Digest calculation failed',
      content: "#{error.message}, stacktrace: #{backtrace}"
    ).call
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
