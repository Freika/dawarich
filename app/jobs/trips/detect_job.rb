# frozen_string_literal: true

# Runs Trip Detection for one user and tells them about the Detected Trips it
# created. The Runner writes the user row itself, so this job never saves the
# user. Runs of one user are serialized by Trips::Detection::RunLock: a run
# that finds the lock taken tries again a minute later.
#
# Every trigger goes through .schedule (ruling R31): a burst of triggers, such
# as the files of one multi-file import, becomes one run once they settle.
class Trips::DetectJob < ApplicationJob
  queue_as :trips

  RETRY_WAIT = 1.minute
  # Long enough for an import batch and its post-processing to settle.
  DEBOUNCE_DELAY = 5.minutes
  LOCK_TTL = 1.hour

  def self.schedule(user_id)
    newly_scheduled = Sidekiq.redis { |redis| redis.set(schedule_key(user_id), 1, nx: true, ex: LOCK_TTL.to_i) }
    set(wait: DEBOUNCE_DELAY).perform_later(user_id) if newly_scheduled
  end

  def self.schedule_key(user_id)
    "trip_detection_run:user:#{user_id}"
  end

  def perform(user_id)
    # Cleared first, so a trigger from now on schedules the next run.
    Sidekiq.redis { |redis| redis.del(self.class.schedule_key(user_id)) }
    user = User.find_by(id: user_id)
    return unless user&.safe_settings&.trip_detection_enabled?

    ran = Trips::Detection::RunLock.try_with(user.id) { detect(user) }
    self.class.set(wait: RETRY_WAIT).perform_later(user_id) unless ran
  end

  private

  def detect(user)
    trips = Trips::Detection::Runner.new(user).call
    return if trips.empty?

    I18n.with_locale(user.locale) do
      Notifications::Create.new(user:, kind: :info, **message(trips)).call
    end
  end

  def message(trips)
    routes = Rails.application.routes.url_helpers

    if trips.one?
      { title: I18n.t('trip_detection.notifications.one.title', name: trips.first.name),
        content: I18n.t('trip_detection.notifications.one.content', url: routes.trip_path(trips.first)) }
    else
      { title: I18n.t('trip_detection.notifications.many.title', count: trips.size),
        content: I18n.t('trip_detection.notifications.many.content', url: routes.trips_path(origin: 'detected')) }
    end
  end
end
