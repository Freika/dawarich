# frozen_string_literal: true

module UserFamily
  extend ActiveSupport::Concern

  included do
    # Family associations
    has_one :family_membership, dependent: :destroy
    has_one :family, through: :family_membership
    has_one :created_family, class_name: 'Family', foreign_key: 'creator_id', inverse_of: :creator, dependent: :destroy
    has_many :sent_family_invitations, class_name: 'FamilyInvitation', foreign_key: 'invited_by_id',
             inverse_of: :invited_by, dependent: :destroy

    before_destroy :check_family_ownership
  end

  def in_family?
    family_membership.present?
  end

  def family_owner?
    family_membership&.owner? == true
  end

  def can_delete_account?
    return true unless family_owner?
    return true unless family

    family.members.count <= 1
  end

  def family_sharing_enabled?
    # User must be in a family and have explicitly enabled location sharing
    return false unless in_family?

    sharing_settings = settings.dig('family', 'location_sharing')
    return false if sharing_settings.blank?

    # If it's a boolean (legacy support), return it
    return sharing_settings if [true, false].include?(sharing_settings)

    # If it's time-limited sharing, check if it's still active
    if sharing_settings.is_a?(Hash)
      return false unless sharing_settings['enabled'] == true

      # Check if sharing has an expiration
      expires_at = sharing_settings['expires_at']
      return expires_at.blank? || Time.parse(expires_at) > Time.current
    end

    false
  end

  def update_family_location_sharing!(enabled, duration: nil)
    return false unless in_family?

    current_settings = settings || {}
    current_settings['family'] ||= {}

    if enabled
      sharing_config = { 'enabled' => true }

      # Add expiration if duration is specified
      if duration.present?
        expiration_time = case duration
        when '1h'
          1.hour.from_now
        when '6h'
          6.hours.from_now
        when '12h'
          12.hours.from_now
        when '24h'
          24.hours.from_now
        when 'permanent'
          nil # No expiration
        else
          duration.to_i.hours.from_now if duration.to_i > 0
        end

        sharing_config['expires_at'] = expiration_time.iso8601 if expiration_time
        sharing_config['duration'] = duration
      end

      current_settings['family']['location_sharing'] = sharing_config
    else
      current_settings['family']['location_sharing'] = { 'enabled' => false }
    end

    update!(settings: current_settings)
  end

  def family_sharing_expires_at
    sharing_settings = settings.dig('family', 'location_sharing')
    return nil unless sharing_settings.is_a?(Hash)

    expires_at = sharing_settings['expires_at']
    Time.parse(expires_at) if expires_at.present?
  rescue ArgumentError
    nil
  end

  def family_sharing_duration
    settings.dig('family', 'location_sharing', 'duration') || 'permanent'
  end

  def latest_location_for_family
    return nil unless family_sharing_enabled?

    # Use select to only fetch needed columns and limit to 1 for efficiency
    latest_point = points.select(:latitude, :longitude, :timestamp)
                         .order(timestamp: :desc)
                         .limit(1)
                         .first

    return nil unless latest_point

    {
      user_id: id,
      email: email,
      latitude: latest_point.latitude,
      longitude: latest_point.longitude,
      timestamp: latest_point.timestamp,
      updated_at: Time.at(latest_point.timestamp)
    }
  end

  private

  def check_family_ownership
    return if can_delete_account?

    errors.add(:base, 'Cannot delete account while being a family owner with other members')
    raise ActiveRecord::DeleteRestrictionError, 'Cannot delete user with family members'
  end
end
