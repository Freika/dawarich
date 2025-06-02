# frozen_string_literal: true

class VisitSuggestingJob < ApplicationJob
  queue_as :visit_suggesting

  # Passing timespan of more than 3 years somehow results in duplicated Places
  def perform(user_id:, start_at:, end_at:)
    user = User.find(user_id)

    start_time = parse_date(start_at)
    end_time = parse_date(end_at)

    # Create one-day chunks
    current_time = start_time
    while current_time < end_time
      chunk_end = [current_time + 1.day, end_time].min
      Visits::Suggest.new(user, start_at: current_time, end_at: chunk_end).call
      current_time += 1.day
    end
  end

  private

  def parse_date(date)
    date.is_a?(String) ? Time.zone.parse(date) : date.to_datetime
  end
end
