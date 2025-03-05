# frozen_string_literal: true

class VisitSuggestingJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: false

  def perform(user_ids: [], start_at: 1.day.ago, end_at: Time.current)
    users = user_ids.any? ? User.where(id: user_ids) : User.all
    start_at = start_at.to_datetime
    end_at = end_at.to_datetime

    users.find_each do |user|
      next unless user.active?
      next if user.tracked_points.empty?

      # Split the time range into 24-hour chunks
      # This prevents from places duplicates
      time_chunks = (start_at..end_at).step(1.day).to_a

      time_chunks.each do |time_chunk|
        Visits::Suggest.new(user, start_at: time_chunk, end_at: time_chunk + 1.day).call
      end
    end
  end
end
