# frozen_string_literal: true

module Webhooks
  class CleanupDeliveriesJob < ApplicationJob
    queue_as :webhooks

    def perform
      WebhookDelivery.old.delete_all
      GeofenceEvent.where(synthetic: true, created_at: ...30.days.ago).delete_all
    end
  end
end
