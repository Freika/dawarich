# frozen_string_literal: true

module Webhooks
  class CleanupDeliveriesJob < ApplicationJob
    queue_as :default

    def perform
      WebhookDelivery.old.delete_all
    end
  end
end
