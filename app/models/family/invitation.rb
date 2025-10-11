# frozen_string_literal: true

class Family::Invitation < ApplicationRecord
  self.table_name = 'family_invitations'

  EXPIRY_DAYS = 7

  belongs_to :family
  belongs_to :invited_by, class_name: 'User'

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, :status, presence: true

  enum :status, { pending: 0, accepted: 1, expired: 2, cancelled: 3 }

  scope :active, -> { where(status: :pending).where('expires_at > ?', Time.current) }

  before_validation :generate_token, :set_expiry, on: :create

  after_create :clear_family_cache
  after_update :clear_family_cache, if: :saved_change_to_status?
  after_destroy :clear_family_cache

  def expired?
    expires_at.past?
  end

  def can_be_accepted?
    pending? && !expired?
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32) if token.blank?
  end

  def set_expiry
    self.expires_at = EXPIRY_DAYS.days.from_now if expires_at.blank?
  end

  def clear_family_cache
    family.clear_member_cache!
  end
end
