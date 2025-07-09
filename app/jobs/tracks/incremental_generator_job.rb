# frozen_string_literal: true

class Tracks::IncrementalGeneratorJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 3

  def perform(user_id, day = nil, grace_period_minutes = 5)
    user = User.find(user_id)
    day = day ? Date.parse(day.to_s) : Date.current

    Rails.logger.info "Starting incremental track generation for user #{user.id}, day #{day}"

    generator(user, day, grace_period_minutes).call
  rescue StandardError => e
    ExceptionReporter.call(e, 'Incremental track generation failed')

    raise e
  end

  private

  def generator(user, day, grace_period_minutes)
    @generator ||= Tracks::Generator.new(
      user,
      point_loader: Tracks::PointLoaders::IncrementalLoader.new(user, day),
      incomplete_segment_handler: Tracks::IncompleteSegmentHandlers::BufferHandler.new(user, day, grace_period_minutes),
      track_cleaner: Tracks::Cleaners::NoOpCleaner.new(user)
    )
  end
end
