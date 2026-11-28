# frozen_string_literal: true

module Analytics
  # Sends a recorded event to Rybbit. A failure raises, so Sidekiq retries it
  # with backoff; delivered_at keeps a retry from sending it twice.
  class DeliverEventJob < ApplicationJob
    queue_as :analytics
    sidekiq_options retry: 10

    PATHNAMES = { 'import_succeeded' => '/imports' }.freeze

    def perform(event_id)
      event = AnalyticsEvent.find_by(id: event_id)
      return if event.nil? || event.delivered_at

      Rybbit.track(event_name: event.event, properties: event.properties, pathname: PATHNAMES.fetch(event.event, '/'))
      event.update!(delivered_at: Time.current)
    end
  end
end
