# frozen_string_literal: true

class Users::Digests::CalculatingJob < ApplicationJob
  queue_as :digests

  def perform(user_id, year)
    Users::Digests::CalculateYear.new(user_id, year).call
  rescue StandardError => e
    create_digest_failed_notification(user_id, e)
  end

  private

  def create_digest_failed_notification(user_id, error)
    user = User.find(user_id)

    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Year-End Digest calculation failed',
      content: "#{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
