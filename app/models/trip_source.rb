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

  # Validate again immediately before an outbound request. This catches a
  # URL that is now invalid or resolves to a blocked network; the HTTP client
  # also refuses redirects. IP pinning remains a separate hardening step.
  def verify_base_url!
    validate_integration_url!(base_url)
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
