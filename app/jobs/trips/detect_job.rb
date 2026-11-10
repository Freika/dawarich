# frozen_string_literal: true

# Runs Trip Detection for one user and tells them about the Detected Trips it
# created. The Runner writes the user row itself, so this job never saves the
# user. A RecordNotUnique from a simultaneous run is left to the retry, which
# finds the trips in place and creates nothing.
class Trips::DetectJob < ApplicationJob
  queue_as :trips

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.safe_settings&.trip_detection_enabled?

    trips = Trips::Detection::Runner.new(user).call
    return if trips.empty?

    I18n.with_locale(user.locale) do
      Notifications::Create.new(user:, kind: :info, **message(trips)).call
    end
  end

  private

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
