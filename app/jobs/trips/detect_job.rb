# frozen_string_literal: true

# Runs Trip Detection for one user and tells them about the Detected Trips it
# created. The Runner writes the user row itself, so this job never saves the
# user. Runs of one user are serialized by Trips::Detection::RunLock: a run
# that finds the lock taken tries again a minute later.
#
# Every trigger goes through .schedule (ruling R31): a burst of triggers, such
# as the files of one multi-file import, becomes one run once they settle.
#
# An operator stops it for the whole instance by adding a disabled
# `trip_detection` flag at /admin/flipper, or limits it to some users through
# that flag's actor, group or percentage gates; with no flag it runs.
class Trips::DetectJob < ApplicationJob
  queue_as :trips
  # Each retry rescans the user's whole history; the next trigger or night tries again.
  sidekiq_options retry: 3
  # A retry would hit the same statement timeout; the next trigger or night tries again.
  discard_on ActiveRecord::QueryCanceled do |job, error|
    ExceptionReporter.call(error, "Trip detection timed out for user #{job.arguments.first}")
  end

  RETRY_WAIT = 1.minute
  # Long enough for an import batch and its post-processing to settle.
  DEBOUNCE_DELAY = 5.minutes
  LOCK_TTL = 1.hour

  def self.schedule(user_id)
    newly_scheduled = Sidekiq.redis { |redis| redis.set(schedule_key(user_id), 1, nx: true, ex: LOCK_TTL.to_i) }
    return unless newly_scheduled

    begin
      set(wait: DEBOUNCE_DELAY).perform_later(user_id)
    rescue StandardError
      Sidekiq.redis { |redis| redis.del(schedule_key(user_id)) }
      raise
    end
  end

  # With a user, whether detection may run for them; without one, whether it may run for anyone.
  def self.instance_enabled?(user = nil)
    return true unless Flipper.exist?(:trip_detection)

    user ? Flipper.enabled?(:trip_detection, user) : Flipper[:trip_detection].state != :off
  end

  def self.schedule_key(user_id)
    "trip_detection_run:user:#{user_id}"
  end

  def perform(user_id)
    # Cleared first, so a trigger from now on schedules the next run.
    Sidekiq.redis { |redis| redis.del(self.class.schedule_key(user_id)) }
    user = User.find_by(id: user_id)
    return unless user&.safe_settings&.trip_detection_enabled? && self.class.instance_enabled?(user)

    ran = Trips::Detection::RunLock.try_with(user.id) { detect(user) }
    self.class.set(wait: RETRY_WAIT).perform_later(user_id) unless ran
  end

  private

  def detect(user)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    trips = Trips::Detection::Runner.new(user).call
    Rails.logger.info(format('Trip detection: user %<id>d, %<created>d created, %<seconds>.2fs',
                             id: user.id, created: trips.size,
                             seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started))
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
