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
      Notifications::Create.new(
        user: user,
        title: 'AirTrail sync failed',
        content: "Your AirTrail flight sync failed with error: #{error.message}. " \
                 'Check your AirTrail settings and try again.',
        kind: :error
      ).call
    end
  end
end
