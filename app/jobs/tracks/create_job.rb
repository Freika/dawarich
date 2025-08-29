# frozen_string_literal: true

class Tracks::CreateJob < ApplicationJob
  queue_as :tracks

  def perform(user_id, start_at: nil, end_at: nil, mode: :daily)
    user = User.find(user_id)

    Tracks::Generator.new(user, start_at:, end_at:, mode:).call
  rescue StandardError => e
    ExceptionReporter.call(
      e,
      "Failed to create tracks for user #{user_id} (mode: #{mode}, start_at: #{start_at.inspect}, end_at: #{end_at.inspect})"
    )
  end
end
