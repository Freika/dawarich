# frozen_string_literal: true

class BulkVisitsSuggestingJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false

  # Passing timespan of more than 3 years somehow results in duplicated Places
  def perform(start_at:, end_at:, user_ids: [])
    users = user_ids.any? ? User.where(id: user_ids) : User.all
    start_at = start_at.to_datetime
    end_at = end_at.to_datetime

    time_chunks = time_chunks(start_at:, end_at:)

    users.active.find_each do |user|
      next if user.tracked_points.empty?

      time_chunks.each do |time_chunk|
        VisitSuggestingJob.perform_later(
          user_id: user.id, start_at: time_chunk.first, end_at: time_chunk.last
        )
      end
    end
  end

  private

  def time_chunks(start_at:, end_at:)
    time_chunks = []

    # First chunk: from start_at to end of that year
    first_end = start_at.end_of_year
    time_chunks << (start_at...first_end) if start_at < first_end

    # Full-year chunks
    current = first_end.beginning_of_year + 1.year # Start from the next full year
    while current + 1.year <= end_at.beginning_of_year
      time_chunks << (current...current + 1.year)
      current += 1.year
    end

    # Last chunk: from start of the last year to end_at
    time_chunks << (current...end_at) if current < end_at

    time_chunks
  end
end
