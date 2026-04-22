# frozen_string_literal: true

class GeofenceEvent < ApplicationRecord
  belongs_to :user
  belongs_to :area
  has_many :webhook_deliveries, dependent: :destroy

  enum :event_type, { enter: 0, leave: 1 }, prefix: :event_type
  enum :source, { native_app: 0, server_inferred: 1, owntracks_native: 2 }, prefix: :source

  validates :event_type, :source, :occurred_at, :received_at, presence: true
end
