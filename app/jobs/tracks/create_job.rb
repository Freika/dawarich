# frozen_string_literal: true

class Tracks::CreateJob < ApplicationJob
  queue_as :default

  def perform(user_id, start_at: nil, end_at: nil, cleaning_strategy: :replace)
    user = User.find(user_id)
    tracks_created = Tracks::CreateFromPoints.new(user, start_at:, end_at:, cleaning_strategy:).call

    create_success_notification(user, tracks_created)
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to create tracks for user')

    create_error_notification(user, e)
  end

  private

  def create_success_notification(user, tracks_created)
    Notifications::Create.new(
      user: user,
      kind: :info,
      title: 'Tracks Generated',
      content: "Created #{tracks_created} tracks from your location data. Check your tracks section to view them."
    ).call
  end

  def create_error_notification(user, error)
    Notifications::Create.new(
      user: user,
      kind: :error,
      title: 'Track Generation Failed',
      content: "Failed to generate tracks from your location data: #{error.message}"
    ).call
  end
end
