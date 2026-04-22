# frozen_string_literal: true

class Webhook < ApplicationRecord
  belongs_to :user
  has_many :webhook_deliveries, dependent: :destroy

  validates :name, :url, presence: true

  before_validation :ensure_secret

  def regenerate_secret!
    update!(secret: self.class.generate_secret)
  end

  def subscribed_to?(area:, event_type:)
    return false unless active?

    event_type_int = self.class.event_types_int[event_type.to_s]
    return false if event_type_int.nil?
    return false unless event_types.include?(event_type_int)

    area_ids.empty? || area_ids.include?(area.id)
  end

  def self.generate_secret
    SecureRandom.hex(32)
  end

  def self.event_types_int
    { 'enter' => 0, 'leave' => 1 }
  end

  private

  def ensure_secret
    self.secret ||= self.class.generate_secret
  end
end
