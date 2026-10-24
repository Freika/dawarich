# frozen_string_literal: true

class Webhook < ApplicationRecord
  include UrlValidatable

  EVENT_TYPES = { 'enter' => 0, 'leave' => 1 }.freeze

  belongs_to :user
  has_many :webhook_deliveries, dependent: :delete_all

  MAX_PER_USER = 10

  validates :name, :url, presence: true
  validate :event_types_known
  validate :areas_owned
  validate :within_limit, on: :create
  validate :url_is_allowed, if: -> { url.present? && will_save_change_to_url? }

  before_validation :ensure_secret
  before_save :reset_failures, if: -> { will_save_change_to_active?(from: false, to: true) }

  def self.generate_secret
    SecureRandom.hex(32)
  end

  def regenerate_secret!
    update!(secret: self.class.generate_secret)
  end

  def resolved_url_ip!
    resolve_integration_url!(url)
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

  def url_is_allowed
    if !DawarichSettings.self_hosted? && URI.parse(url).scheme != 'https'
      errors.add(:url, :https_required)
      return
    end

    validate_integration_url!(url)
  rescue URI::InvalidURIError
    errors.add(:url, I18n.t('services.concerns.url_validatable.invalid_format'))
  rescue UrlValidatable::BlockedUrlError => e
    errors.add(:url, e.message)
  end

  def event_types_known
    return if event_types.present? && (event_types - EVENT_TYPES.values).empty?

    errors.add(:event_types, :invalid)
  end

  def areas_owned
    return if area_ids.blank?
    return if user && user.areas.where(id: area_ids).count == area_ids.uniq.size

    errors.add(:area_ids, :invalid)
  end

  def within_limit
    return unless user && user.webhooks.count >= MAX_PER_USER

    errors.add(:base, :too_many, count: MAX_PER_USER)
  end

  def reset_failures
    self.consecutive_failures = 0
  end
end
