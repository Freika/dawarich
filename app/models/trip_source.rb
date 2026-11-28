# frozen_string_literal: true

class TripSource < ApplicationRecord
  include UrlValidatable

  PROVIDERS = %w[trek].freeze

  belongs_to :user
  has_many :trips, dependent: :restrict_with_error

  encrypts :api_key

  enum :status, { active: 0, disabled: 1 }, default: :active

  validates :provider, inclusion: { in: PROVIDERS }
  validates :base_url, presence: true, uniqueness: { scope: %i[user_id provider] }
  validates :api_key, presence: true
  validate :base_url_is_allowed

  before_validation :normalize_base_url

  def skips_ssl_verification?
    skip_ssl_verification && base_url.to_s.match?(%r{\Ahttps://}i)
  end

  def sync_allowed?
    user.full_access?
  end

  private

  def normalize_base_url
    self.base_url = base_url.to_s.strip.chomp('/') if base_url.present?
  end

  def base_url_is_allowed
    validate_integration_url!(base_url)
  rescue UrlValidatable::BlockedUrlError => e
    errors.add(:base_url, e.message)
  end
end
