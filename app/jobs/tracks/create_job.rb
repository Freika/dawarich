# frozen_string_literal: true

class Tracks::CreateJob < ApplicationJob
  queue_as :tracks

  def perform(user_id, start_at: nil, end_at: nil, mode: :daily)
    user = User.find(user_id)

    # Translate mode parameter to Generator mode
    generator_mode = case mode
                    when :daily then :daily
                    when :none then :incremental
                    else :bulk
                    end

    # Generate tracks and get the count of tracks created
    tracks_created = Tracks::Generator.new(
      user,
      start_at: start_at,
      end_at: end_at,
      mode: generator_mode
    ).call

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
