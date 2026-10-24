# frozen_string_literal: true

class Webhook < ApplicationRecord
  EVENT_TYPES = { 'enter' => 0, 'leave' => 1 }.freeze

  belongs_to :user
  has_many :webhook_deliveries, dependent: :delete_all

  validates :name, :url, presence: true

  before_validation :ensure_secret
  before_save :reset_failures, if: -> { will_save_change_to_active?(from: false, to: true) }

  def self.generate_secret
    SecureRandom.hex(32)
  end

  def regenerate_secret!
    update!(secret: self.class.generate_secret)
  end

  def subscribed_to?(area:, event_type:)
    return false unless active?

    event_type_value = EVENT_TYPES[event_type.to_s]
    return false unless event_type_value && event_types.include?(event_type_value)

    area_ids.empty? || area_ids.include?(area.id)
  end

  def serializable_hash(options = nil)
    options = (options || {}).dup
    options[:except] = Array(options[:except]) + [:secret]
    super
  end

  private

  def ensure_secret
    self.secret ||= self.class.generate_secret
  end

  def reset_failures
    self.consecutive_failures = 0
  end
end
