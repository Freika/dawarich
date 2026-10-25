# frozen_string_literal: true

class GeofenceEvent < ApplicationRecord
  belongs_to :user
  belongs_to :place
  has_many :webhook_deliveries, dependent: :delete_all

  enum :event_type, { enter: 0, leave: 1 }, prefix: :event_type
  enum :source, { native_app: 0, server_inferred: 1, owntracks_native: 2 }, prefix: :source

  validates :event_type, :source, :occurred_at, :received_at, presence: true

  WEBHOOK_FRESHNESS = 15.minutes

  scope :real, -> { where(synthetic: false) }

  def stale_for_webhooks?
    received_at - occurred_at > WEBHOOK_FRESHNESS
  end
end
