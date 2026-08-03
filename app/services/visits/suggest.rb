# frozen_string_literal: true

class Visits::Suggest
  attr_reader :user, :start_at, :end_at

  def initialize(user, start_at:, end_at:)
    @start_at = start_at.to_i
    @end_at = end_at.to_i
    @user = user
  end

  def call
    visits = Visits::SmartDetect.new(user, start_at:, end_at:).call
    return visits if visits.empty?

    create_visits_notification(user)
    if DawarichSettings.reverse_geocoding_enabled?
      visits.filter_map(&:place_id).uniq.each do |place_id|
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

  ERROR_TITLE = 'Error suggesting visits'
  ERROR_DEDUP_WINDOW = 1.hour

  # The debouncer can schedule a run every five minutes; without this an outage
  # would bury the notification list under hundreds of identical rows. The claim
  # is a Redis SET NX so two concurrent runs can't both pass the check, and it
  # fails open — a Redis problem must never swallow the error notification.
  def notify_failure(error)
    return unless claim_error_window?

    user.notifications.create!(
      kind: :error,
      title: ERROR_TITLE,
      content: I18n.t('services.visits.suggest.error_suggesting_visits_message', message: error.message)
    )
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
    content = <<~CONTENT
      New visits have been suggested based on your location data from #{Time.zone.at(start_at)} to #{Time.zone.at(end_at)}. You can review them on the <a href="/map/v2?panel=timeline&date=today&status=suggested" class="link">Timeline</a> page.
    CONTENT

    user.notifications.create!(
      kind: :info,
      title: I18n.t('services.visits.suggest.new_visits_suggested'),
      content:
    )
  end
end
