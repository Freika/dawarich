# frozen_string_literal: true

class BulkVisitsSuggestingJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  # Passing timespan of more than 3 years somehow results in duplicated Places
  def perform(start_at:, end_at:, user_ids: [])
    users = user_ids.any? ? User.where(id: user_ids) : User.all
    start_at = start_at.to_datetime
    end_at = end_at.to_datetime

    time_chunks = Visits::TimeChunks.new(start_at:, end_at:).call

    users.active.find_each do |user|
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
