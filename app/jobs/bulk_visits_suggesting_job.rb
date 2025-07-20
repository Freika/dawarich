# frozen_string_literal: true

# This job is being run on daily basis at 00:05 to suggest visits for all users
# with the default timespan of 1 day.
class BulkVisitsSuggestingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  # Passing timespan of more than 3 years somehow results in duplicated Places
  def perform(start_at: 1.day.ago.beginning_of_day, end_at: 1.day.ago.end_of_day, user_ids: [])
    return unless DawarichSettings.reverse_geocoding_enabled?

    users = user_ids.any? ? User.active.where(id: user_ids) : User.active
    users = users.select { _1.safe_settings.visits_suggestions_enabled? }

    start_at = start_at.to_datetime
    end_at = end_at.to_datetime

    time_chunks = Visits::TimeChunks.new(start_at:, end_at:).call

    users.find_each do |user|
      next if user.tracked_points.empty?

      schedule_chunked_jobs(user, time_chunks)
    end
  end

  private

  def schedule_chunked_jobs(user, time_chunks)
    time_chunks.each do |time_chunk|
      VisitSuggestingJob.perform_later(
        user_id: user.id, start_at: time_chunk.first, end_at: time_chunk.last
      )
    end
  end
end
