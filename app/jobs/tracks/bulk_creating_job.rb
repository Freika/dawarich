# frozen_string_literal: true

# This job is being run on daily basis to create tracks for all users.
# For each user, it starts from the end of their last track (or from their oldest point
# if no tracks exist) and processes points until the specified end_at time.
#
# To manually run for a specific time range:
#   Tracks::BulkCreatingJob.perform_later(start_at: 1.week.ago, end_at: Time.current)
#
# To run for specific users only:
#   Tracks::BulkCreatingJob.perform_later(user_ids: [1, 2, 3])
#
# To let the job determine start times automatically (recommended):
#   Tracks::BulkCreatingJob.perform_later(end_at: Time.current)
class Tracks::BulkCreatingJob < ApplicationJob
  queue_as :tracks
  sidekiq_options retry: false

  def perform(start_at: nil, end_at: 1.day.ago.end_of_day, user_ids: [])
    Tracks::BulkTrackCreator.new(start_at:, end_at:, user_ids:).call
  end
end
