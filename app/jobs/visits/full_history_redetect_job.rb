# frozen_string_literal: true

class Visits::FullHistoryRedetectJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: 0

  BATCH_OVERLAP_SECONDS = 1.hour.to_i
  COOLDOWN = 1.hour

  def perform(user_id)
    user = User.find(user_id)

    if recently_redetected?(user)
      Rails.logger.info("[Visits::FullHistoryRedetectJob skip] user_id=#{user.id} reason=cooldown_active")
      return
    end

    Tracks::PerUserLock.with_user_lock(user_id) do
      user.reload
      if recently_redetected?(user)
        Rails.logger.info("[Visits::FullHistoryRedetectJob skip] user_id=#{user.id} reason=cooldown_active_after_lock")
        next
      end

      run_redetection(user)
    end
  rescue Tracks::PerUserLock::AcquisitionTimeout => e
    Rails.logger.warn(
      "[Visits::FullHistoryRedetectJob lock_timeout] user_id=#{user_id} message=#{e.message}"
    )
    user_for_notify = defined?(user) ? user : User.find_by(id: user_id)
    if user_for_notify
      notify!(
        user_for_notify, kind: :warning, title: 'Visit re-detection busy',
        content: 'Another re-detection is already running. Try again in a few minutes.'
      )
    end
  rescue StandardError => e
    Rails.logger.error(
      "[Visits::FullHistoryRedetectJob error] user_id=#{user_id} " \
      "class=#{e.class} message=#{e.message}"
    )
    user_for_notify = defined?(user) ? user : User.find_by(id: user_id)
    notify_failure(user_for_notify, e) if user_for_notify
    ExceptionReporter.call(e)
    raise
  end

  private

  def run_redetection(user)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    min_ts = user.points.minimum(:timestamp)
    max_ts = user.points.maximum(:timestamp)

    if min_ts.nil?
      notify!(user, kind: :info, title: 'Visit re-detection',
                    content: 'No points to re-detect.')
      return
    end

    Rails.logger.info(
      "[Visits::FullHistoryRedetectJob start] user_id=#{user.id} " \
      "point_range=#{min_ts}..#{max_ts}"
    )

    visit_ids = user.visits.where(status: :suggested).pluck(:id)
    place_ids_direct    = Visit.where(id: visit_ids).where.not(place_id: nil).pluck(:place_id)
    place_ids_suggested = PlaceVisit.where(visit_id: visit_ids).pluck(:place_id)
    candidate_place_ids = (place_ids_direct + place_ids_suggested).uniq

    Visit.where(id: visit_ids).find_each(&:destroy)

    months = monthly_ranges(min_ts, max_ts)
    visits_created = 0
    months_failed = []

    months.each do |range_start, range_end|
      visits_created += Visits::SmartDetect.new(user, start_at: range_start, end_at: range_end).call.size
    rescue StandardError => e
      months_failed << [range_start, range_end]
      Rails.logger.error(
        "[Visits::FullHistoryRedetectJob month_failed] user_id=#{user.id} " \
        "range=#{range_start}..#{range_end} class=#{e.class} message=#{e.message}"
      )
      ExceptionReporter.call(e)
    end

    places_deleted = cleanup_orphan_places(user, candidate_place_ids)

    user.update!(visits_redetected_at: Time.current)

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
    Rails.logger.info(
      "[Visits::FullHistoryRedetectJob done] user_id=#{user.id} " \
      "visits_created=#{visits_created} places_deleted=#{places_deleted} " \
      "months_processed=#{months.size - months_failed.size}/#{months.size} duration_ms=#{duration_ms}"
    )

    if months_failed.empty?
      notify!(user, kind: :info, title: 'Visit re-detection complete',
                    content: "#{visits_created} visits across #{months.size} months.")
    else
      ok_months = months.size - months_failed.size
      notify!(user, kind: :warning, title: 'Visit re-detection partially complete',
                    content: "#{visits_created} visits across #{ok_months} of #{months.size} months. " \
                             "#{months_failed.size} month(s) failed; re-run after the cooldown to retry.")
    end
  end

  def recently_redetected?(user)
    last = user.visits_redetected_at
    last.present? && last > COOLDOWN.ago
  end

  def monthly_ranges(min_ts, max_ts)
    result = []
    cursor = Time.zone.at(min_ts).beginning_of_month
    while cursor.to_i < max_ts
      batch_start = [cursor.to_i, min_ts].max
      batch_end_raw = (cursor.end_of_month + 1.day).beginning_of_day.to_i - 1
      batch_end = [batch_end_raw + BATCH_OVERLAP_SECONDS, max_ts].min
      result << [batch_start, batch_end]
      cursor = cursor.next_month
    end
    result
  end

  def cleanup_orphan_places(user, candidate_place_ids)
    return 0 if candidate_place_ids.empty?

    deleted = 0
    Place.photon.where(id: candidate_place_ids, user_id: user.id).find_each do |place|
      next if place.visits.exists? || place.place_visits.exists?

      place.destroy
      deleted += 1
    end
    deleted
  end

  def notify_failure(user, error)
    notify!(user, kind: :error, title: 'Visit re-detection failed', content: error.message)
  end

  def notify!(user, kind:, title:, content:)
    user.notifications.create!(kind: kind, title: title, content: content)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn(
      "[Visits::FullHistoryRedetectJob notify] user_id=#{user&.id} kind=#{kind} error=#{e.message}"
    )
  end
end
