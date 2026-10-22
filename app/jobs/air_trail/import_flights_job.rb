# frozen_string_literal: true

module AirTrail
  class ImportFlightsJob < ApplicationJob
    queue_as :imports

    def perform(user_id)
      user = find_user_or_skip(user_id) || return

      AirTrail::ImportFlights.new(user).call
    rescue AirTrail::Client::Error => e
      ExceptionReporter.call(e, "AirTrail sync failed for user #{user_id}")
      notify_sync_failed(user, e)

      raise e
    end

    private

    def notify_sync_failed(user, error)
      I18n.with_locale(user.locale) do
        Notifications::Create.new(
          user: user,
          title: I18n.t('jobs.air_trail.import_flights_job.airtrail_sync_failed'),
          content: I18n.t(
            'jobs.air_trail.import_flights_job.your_airtrail_flight_sync_failed_with_error_message_check_your',
            message: error.message
          ),
          kind: :error
        ).call
      end
    end
  end
end
