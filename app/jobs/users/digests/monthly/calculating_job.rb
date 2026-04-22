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

  def create_digest_failed_notification(user_id, error)
    user = find_user_or_skip(user_id) || return

    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Monthly Digest calculation failed',
      content: "#{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
