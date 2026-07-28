# frozen_string_literal: true

class VisitSuggestingJob < ApplicationJob
  include UserTimezone

  queue_as :visit_suggesting
  sidekiq_options retry: false

  # Passing timespan of more than 3 years somehow results in duplicated Places
  def perform(user_id:, start_at:, end_at:)
    release_debounce_key(user_id)

    user = find_user_or_skip(user_id) || return

    return unless user.safe_settings.visits_suggestions_enabled?

    with_user_timezone(user) do
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
  end

  private

  # retry: false means a transient Redis blip here would otherwise drop the whole run.
  def release_debounce_key(user_id)
    Visits::RealtimeDebouncer.new(user_id).clear
  rescue StandardError => e
    Rails.logger.warn("[VisitSuggestingJob] debounce key release failed user_id=#{user_id}: #{e.class}: #{e.message}")
  end

  def parse_date(date)
    date.is_a?(String) ? Time.zone.parse(date) : date.to_datetime
  end
end
