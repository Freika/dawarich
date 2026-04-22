# frozen_string_literal: true

class Webhook < ApplicationRecord
  belongs_to :user
  has_many :webhook_deliveries, dependent: :destroy

  validates :name, :url, presence: true
  validate :url_is_safe, if: -> { url.present? && url_changed? }

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

  # secret is symmetric HMAC key; never expose in default serializations
  def serializable_hash(options = nil)
    super((options || {}).merge(except: Array(options&.fetch(:except, nil)) + [:secret]))
  end

  private

  def url_is_safe
    validation = Webhooks::UrlValidator.call(url.to_s)
    errors.add(:url, "is not allowed (#{validation})") unless validation == :ok
  end

  def ensure_secret
    self.secret ||= self.class.generate_secret
  end
end
