# frozen_string_literal: true

class Family::LocationRequest < ApplicationRecord
  self.table_name = 'family_location_requests'

  belongs_to :requester, class_name: 'User'
  belongs_to :target_user, class_name: 'User'
  belongs_to :family

  validates :requester_id, presence: true
  validates :target_user_id, presence: true
  validates :family_id, presence: true
  validates :expires_at, presence: true
  validate :requester_cannot_be_target

  enum :status, { pending: 0, accepted: 1, declined: 2, expired: 3 }

  scope :active, -> { pending.where('expires_at > ?', Time.current) }

  before_validation :set_defaults, on: :create

  private

  def requester_cannot_be_target
    return unless requester_id.present? && requester_id == target_user_id

    errors.add(:requester_id, 'cannot request your own location')
  end

  def set_defaults
    self.expires_at ||= 24.hours.from_now
    self.suggested_duration ||= '24h'
  end
end
