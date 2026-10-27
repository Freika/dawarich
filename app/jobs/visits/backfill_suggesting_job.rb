# frozen_string_literal: true

class Visits::BackfillSuggestingJob < ApplicationJob
  queue_as :visit_suggesting

  PADDING = 6.hours

  def perform(user_id)
    range = Visits::BackfillScheduler.pop_range(user_id)
    return unless range

    user = User.find_by(id: user_id)
    return unless user&.safe_settings&.visits_suggestions_enabled?

    now = Time.current
    oldest = Visits::BackfillScheduler::MAX_AGE.ago(now)
    return if range.last < oldest.to_i

    VisitSuggestingJob.perform_later(
      user_id: user_id,
      start_at: [Time.zone.at(range.first) - PADDING, oldest].max,
      end_at: [Time.zone.at(range.last) + PADDING, now].min,
      release_debounce: false
    )
  rescue StandardError => e
    Visits::BackfillScheduler.new(user_id, range).call if range
    ExceptionReporter.call(e, "Failed to schedule backfill visit suggestions for user #{user_id}")
  end
end
