# frozen_string_literal: true

class WebhookDelivery < ApplicationRecord
  belongs_to :webhook
  belongs_to :geofence_event

  enum :status, { pending: 0, success: 1, failure: 2, retrying: 3 }, prefix: :status

  scope :old, -> { where('created_at < ?', 30.days.ago) }
end
