# frozen_string_literal: true

module UserFamily
  extend ActiveSupport::Concern

  # Family ownership check for deletion is handled by:
  # - Controller: checks can_delete_account? before soft-deleting
  # - Users::Destroy service: validates before hard-deleting

  included do
    has_one :family_membership, dependent: :destroy, class_name: 'Family::Membership'
    has_one :family, through: :family_membership
    has_one :created_family, class_name: 'Family', foreign_key: 'creator_id', inverse_of: :creator, dependent: :destroy
    has_many :sent_family_invitations, class_name: 'Family::Invitation', foreign_key: 'invited_by_id',
             inverse_of: :invited_by, dependent: :destroy
    has_many :sent_location_requests, class_name: 'Family::LocationRequest', foreign_key: 'requester_id',
             inverse_of: :requester, dependent: :destroy
    has_many :received_location_requests, class_name: 'Family::LocationRequest', foreign_key: 'target_user_id',
             inverse_of: :target_user, dependent: :destroy
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
    return false unless in_family?

    sharing_settings = settings.dig('family', 'location_sharing')
    return false unless sharing_settings.is_a?(Hash)
    return false unless sharing_settings['enabled'] == true

    expires_at = sharing_settings['expires_at']
    expires_at.blank? || Time.zone.parse(expires_at).future?
  end

  def update_family_location_sharing!(enabled, duration: nil, share_history: nil, history_window: nil)
    return false unless in_family?

    current_settings = settings || {}
    current_settings['family'] ||= {}

    if enabled
      existing_started_at = current_settings.dig('family', 'location_sharing', 'started_at')
      existing_share_history = current_settings.dig('family', 'location_sharing', 'share_history')
      existing_history_window = current_settings.dig('family', 'location_sharing', 'history_window')

      sharing_config = { 'enabled' => true }
      sharing_config['started_at'] = existing_started_at || Time.current.iso8601
      sharing_config['share_history'] = share_history.nil? ? (existing_share_history || false) : share_history
      validated_window = validate_history_window(history_window || existing_history_window)
      sharing_config['history_window'] = validated_window

      if duration.present?
        expiration_time = case duration
                          when '1h' then 1.hour.from_now
                          when '6h' then 6.hours.from_now
                          when '12h' then 12.hours.from_now
                          when '24h' then 24.hours.from_now
                          when 'permanent' then nil
                          else duration.to_i.hours.from_now if duration.to_i.positive?
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
    Time.zone.parse(expires_at) if expires_at.present?
  rescue ArgumentError
    nil
  end

  def family_sharing_duration
    settings.dig('family', 'location_sharing', 'duration') || 'permanent'
  end

  def family_sharing_started_at
    started_at = settings.dig('family', 'location_sharing', 'started_at')
    return nil if started_at.blank?

    Time.zone.parse(started_at)
  rescue ArgumentError
    nil
  end

  def family_share_history?
    settings.dig('family', 'location_sharing', 'share_history') == true
  end

  def family_history_window
    settings.dig('family', 'location_sharing', 'history_window') || '24h'
  end

  # Returns points within the given date range, scoped by sharing start time,
  # history window preference, and capped at 1 year maximum.
  # Points are ordered by timestamp ascending.
  def family_history_points(start_at:, end_at:)
    return Point.none unless family_sharing_enabled?
    return Point.none unless family_share_history?

    started_at = family_sharing_started_at
    return Point.none unless started_at

    # Apply history window preference
    window_start = case family_history_window
                   when '24h' then 24.hours.ago
                   when '7d' then 7.days.ago
                   when '30d' then 30.days.ago
                   when 'all' then 1.year.ago
                   else 24.hours.ago
                   end

    effective_start = [start_at, started_at, window_start].max

    return Point.none if effective_start >= end_at

    scoped_points
      .where('timestamp >= ? AND timestamp <= ?', effective_start.to_i, end_at.to_i)
      .order(timestamp: :asc)
  end

  VALID_HISTORY_WINDOWS = %w[24h 7d 30d all].freeze

  def latest_location_for_family
    return nil unless family_sharing_enabled?

    latest_point =
      points.select(:lonlat, :timestamp)
            .order(timestamp: :desc)
            .limit(1)
            .first

    return nil unless latest_point

    {
      user_id: id,
      email: email,
      latitude: latest_point.lat,
      longitude: latest_point.lon,
      timestamp: latest_point.timestamp,
      updated_at: Time.zone.at(latest_point.timestamp)
    }
  end

  private

  def validate_history_window(window)
    VALID_HISTORY_WINDOWS.include?(window) ? window : '24h'
  end
end
