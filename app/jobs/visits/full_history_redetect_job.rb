# frozen_string_literal: true

class Visits::FullHistoryRedetectJob < ApplicationJob
  queue_as :visit_suggesting
  sidekiq_options retry: 0

  COOLDOWN = 1.hour

  def perform(user_id)
    user = User.find(user_id)

    I18n.with_locale(user.locale) do
      if recently_redetected?(user)
        Rails.logger.info("[Visits::FullHistoryRedetectJob skip] user_id=#{user.id} reason=cooldown_active")
        return
      end

      Tracks::PerUserLock.with_user_lock(user_id) do
        user.reload
        if recently_redetected?(user)
          Rails.logger.info(
            "[Visits::FullHistoryRedetectJob skip] user_id=#{user.id} reason=cooldown_active_after_lock"
          )
          next
        end

        run_redetection(user)
      end
    end
  rescue Tracks::PerUserLock::AcquisitionTimeout => e
    Rails.logger.warn(
      "[Visits::FullHistoryRedetectJob lock_timeout] user_id=#{user_id} message=#{e.message}"
    )
    user_for_notify = user || User.find_by(id: user_id)
    if user_for_notify
      I18n.with_locale(user_for_notify.locale) do
        notify!(
          user_for_notify,
          kind: :warning,
          title: I18n.t('jobs.visits.full_history_redetect_job.visit_re_detection_busy'),
          content: I18n.t(
            'jobs.visits.full_history_redetect_job.another_re_detection_is_already_running_try_again_in_a'
          )
        )
      end
    end
  rescue StandardError => e
    Rails.logger.error(
      "[Visits::FullHistoryRedetectJob error] user_id=#{user_id} " \
      "class=#{e.class} message=#{e.message}"
    )
    user_for_notify = user || User.find_by(id: user_id)
    I18n.with_locale(user_for_notify.locale) { notify_failure(user_for_notify, e) } if user_for_notify
    ExceptionReporter.call(e)
    raise
  end

  private

  def run_redetection(user)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    min_ts = user.points.minimum(:timestamp)
    max_ts = user.points.maximum(:timestamp)

    if min_ts.nil?
      notify!(user, kind: :info, title: I18n.t('jobs.visits.full_history_redetect_job.visit_re_detection'),
                    content: I18n.t('jobs.visits.full_history_redetect_job.no_points_to_re_detect'))
      return
    end

    Rails.logger.info(
      "[Visits::FullHistoryRedetectJob start] user_id=#{user.id} " \
      "point_range=#{min_ts}..#{max_ts}"
    )

    # Old machine output is replaced per window by the Persister — a month
    # that fails or gets skipped keeps its existing rows instead of being
    # wiped and never regenerated. Rows outside the point range are purged
    # by HistoryRedetect itself.
    result = Visits::Detection::HistoryRedetect.new(user).call
    visits_created = result.visits_created
    months_failed = result.months_failed
    months_total = result.months_total

    user.update!(visits_redetected_at: Time.current)

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).to_i
    Rails.logger.info(
      "[Visits::FullHistoryRedetectJob done] user_id=#{user.id} " \
      "visits_created=#{visits_created} " \
      "months_processed=#{months_total - months_failed.size}/#{months_total} duration_ms=#{duration_ms}"
    )

    if months_failed.empty?
      visits = localized_count('visits_count', visits_created)
      months_count = localized_count('months_count', months_total)
      content = I18n.t(
        'jobs.visits.full_history_redetect_job.visits_created_visits_across_size_months',
        visits:,
        months: months_count
      )
      notify!(user, kind: :info,
                    title: I18n.t('jobs.visits.full_history_redetect_job.visit_re_detection_complete'),
                    content: content)
    else
      ok_months = months_total - months_failed.size
      visits = localized_count('visits_count', visits_created)
      ok_months_count = localized_count('months_count', ok_months)
      months_count = localized_count('months_count', months_total)
      content = I18n.t(
        'jobs.visits.full_history_redetect_job.visits_created_visits_across_ok_months_of_size_months_size',
        count: months_failed.size,
        visits:,
        ok_months: ok_months_count,
        months: months_count
      )
      notify!(user, kind: :warning,
                    title: I18n.t('jobs.visits.full_history_redetect_job.visit_re_detection_partially_complete'),
                    content: content)
    end
  end

  def recently_redetected?(user)
    last = user.visits_redetected_at
    last.present? && last > COOLDOWN.ago
  end

  def localized_count(key, count)
    I18n.t("jobs.visits.full_history_redetect_job.#{key}", count:)
  end

  def notify_failure(user, error)
    notify!(
      user,
      kind: :error,
      title: I18n.t('jobs.visits.full_history_redetect_job.visit_re_detection_failed'),
      content: error.message
    )
  end

  def notify!(user, kind:, title:, content:)
    user.notifications.create!(kind: kind, title: title, content: content)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn(
      "[Visits::FullHistoryRedetectJob notify] user_id=#{user&.id} kind=#{kind} error=#{e.message}"
    )
  end
end
