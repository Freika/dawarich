# frozen_string_literal: true

class Visits::Suggest
  attr_reader :user, :start_at, :end_at

  def initialize(user, start_at:, end_at:)
    @start_at = start_at.to_i
    @end_at = end_at.to_i
    @user = user
  end

  def call
    known = existing_intervals
    visits = Visits::SmartDetect.new(user, start_at:, end_at:).call
    return visits if visits.empty?

    fresh = visits.reject { |visit| covered_by_known?(visit, known) }
    return visits if fresh.empty?

    create_visits_notification(user)
    if Geocoding::Config.for(user).enabled?
      fresh.filter_map(&:place_id).uniq.each do |place_id|
        ReverseGeocodingJob.perform_later('place', place_id)
      end
    end

    visits
  rescue StandardError => e
    Rails.logger.error(
      "[Visits::Suggest] user_id=#{user.id} range=#{start_at}..#{end_at} " \
      "#{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}"
    )

    notify_failure(e)
    ExceptionReporter.call(e)

    []
  end

  private

  ERROR_DEDUP_WINDOW = 1.hour
  TIMELINE_PATH = '/map/v2?panel=timeline&date=today&status=suggested'

  # Detection replaces machine rows wholesale, so a debounced re-run over an
  # ongoing stay "creates" visits every few minutes. Only a visit that does
  # not overlap any machine row that stood before the run is news.
  def existing_intervals
    user.visits.machine_detected
        .where('started_at <= ? AND ended_at >= ?', Time.zone.at(end_at), Time.zone.at(start_at))
        .pluck(:started_at, :ended_at)
        .map { |started_at, ended_at| [started_at.to_i, ended_at.to_i] }
  end

  def covered_by_known?(visit, known)
    known.any? { |start_ts, end_ts| visit.started_at.to_i < end_ts && visit.ended_at.to_i > start_ts }
  end

  # The debouncer can schedule a run every five minutes; without this an outage
  # would bury the notification list under hundreds of identical rows. The claim
  # is a Redis SET NX so two concurrent runs can't both pass the check, and it
  # fails open — a Redis problem must never swallow the error notification.
  def notify_failure(error)
    return unless claim_error_window?

    I18n.with_locale(user.locale) do
      user.notifications.create!(
        kind: :error,
        title: I18n.t('services.visits.suggest.error_suggesting_visits'),
        content: I18n.t('services.visits.suggest.error_suggesting_visits_message', message: error.message)
      )
    end
  end

  def claim_error_window?
    Sidekiq.redis do |redis|
      redis.set("visit_suggest_error:user:#{user.id}", 1, nx: true, ex: ERROR_DEDUP_WINDOW.to_i)
    end
  rescue StandardError => e
    Rails.logger.warn("[Visits::Suggest] error-notification dedupe unavailable: #{e.class}: #{e.message}")
    true
  end

  def create_visits_notification(user)
    I18n.with_locale(user.locale) do
      user.notifications.create!(
        kind: :info,
        title: I18n.t('services.visits.suggest.new_visits_suggested'),
        content: I18n.t(
          'services.visits.suggest.new_visits_suggested_message',
          start_at: Time.zone.at(start_at), end_at: Time.zone.at(end_at), url: TIMELINE_PATH
        )
      )
    end
  end
end
