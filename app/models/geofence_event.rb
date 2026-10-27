# frozen_string_literal: true

class GeofenceEvent < ApplicationRecord
  belongs_to :user
  belongs_to :place, optional: true
  has_many :webhook_deliveries, dependent: :delete_all

  enum :event_type, { enter: 0, leave: 1 }, prefix: :event_type
  enum :source, { native_app: 0, server_inferred: 1, owntracks_native: 2 }, prefix: :source
  enum :webhook_skip_reason, { late: 0, throttled: 1 }, prefix: :skipped

  validates :event_type, :source, :occurred_at, :received_at, presence: true

  WEBHOOK_FRESHNESS = 15.minutes
  WEBHOOK_HOURLY_LIMIT = 60

  scope :real, -> { where(synthetic: false) }

  def display_place_name
    place&.name || place_name
  end
end
