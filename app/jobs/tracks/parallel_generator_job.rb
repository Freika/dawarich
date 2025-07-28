# frozen_string_literal: true

# Entry point job for parallel track generation
# Coordinates the entire parallel processing workflow
class Tracks::ParallelGeneratorJob < ApplicationJob
  queue_as :tracks

  def perform(user_id, start_at: nil, end_at: nil, mode: :bulk, chunk_size: 1.day)
    user = User.find(user_id)
    
    Rails.logger.info "Starting parallel track generation for user #{user_id} (mode: #{mode})"

    session = Tracks::ParallelGenerator.new(
      user,
      start_at: start_at,
      end_at: end_at,
      mode: mode,
      chunk_size: chunk_size
    ).call

    if session
      Rails.logger.info "Parallel track generation initiated for user #{user_id} (session: #{session.session_id})"
    else
      Rails.logger.warn "No tracks to generate for user #{user_id} (no time chunks created)"
      create_info_notification(user, 0)
    end

  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to start parallel track generation')
    Rails.logger.error "Parallel track generation failed for user #{user_id}: #{e.message}"
    
    create_error_notification(user, e) if user
  end

  private

  def create_info_notification(user, tracks_created)
    Notifications::Create.new(
      user: user,
      kind: :info,
      title: 'Track Generation Complete',
      content: "Generated #{tracks_created} tracks from your location data. Check your tracks section to view them."
    ).call
  end

  def create_error_notification(user, error)
    return unless DawarichSettings.self_hosted?

    Notifications::Create.new(
      user: user,
      kind: :error,
      title: 'Track Generation Failed',
      content: "Failed to generate tracks from your location data: #{error.message}"
    ).call
  end
end