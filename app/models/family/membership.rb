# frozen_string_literal: true

class Family::Membership < ApplicationRecord
  self.table_name = 'family_memberships'

  belongs_to :family
  belongs_to :user

  validates :user_id, presence: true, uniqueness: true
  validates :role, presence: true

  enum :role, { owner: 0, member: 1 }

  after_create :clear_family_cache
  after_update :clear_family_cache
  after_destroy :clear_family_cache
  after_destroy :cleanup_on_departure

  private

  def clear_family_cache
    family.clear_member_cache!
  end

  def cleanup_on_departure
    # Disable location sharing for departing user
    user.update_family_location_sharing!(false) if user.family_sharing_enabled?

    # Expire all pending location requests involving the departing user
    Family::LocationRequest
      .pending
      .where('requester_id = ? OR target_user_id = ?', user_id, user_id)
      .update_all(status: Family::LocationRequest.statuses[:expired], updated_at: Time.current)
  rescue StandardError => e
    ExceptionReporter.call(e, "Error cleaning up on family departure: #{e.message}")
  end
end
