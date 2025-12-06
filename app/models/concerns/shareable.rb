# frozen_string_literal: true

module Shareable
  extend ActiveSupport::Concern

  included do
    before_create :generate_sharing_uuid
  end

  def sharing_enabled?
    sharing_settings.try(:[], 'enabled') == true
  end

  def sharing_expired?
    expiration = sharing_settings.try(:[], 'expiration')
    return false if expiration.blank?

    expires_at_value = sharing_settings.try(:[], 'expires_at')
    return true if expires_at_value.blank?

    expires_at = begin
      Time.zone.parse(expires_at_value)
    rescue StandardError
      nil
    end

    expires_at.present? ? Time.current > expires_at : true
  end

  def public_accessible?
    sharing_enabled? && !sharing_expired?
  end

  def generate_new_sharing_uuid!
    update!(sharing_uuid: SecureRandom.uuid)
  end

  def enable_sharing!(expiration: '1h', **options)
    # Default to 24h if an invalid expiration is provided
    expiration = '24h' unless %w[1h 12h 24h permanent].include?(expiration)

    expires_at = case expiration
                 when '1h' then 1.hour.from_now
                 when '12h' then 12.hours.from_now
                 when '24h' then 24.hours.from_now
                 when 'permanent' then nil
                 end

    settings = {
      'enabled' => true,
      'expiration' => expiration,
      'expires_at' => expires_at&.iso8601
    }

    # Merge additional options (like share_notes, share_photos)
    settings.merge!(options.stringify_keys)

    update!(
      sharing_settings: settings,
      sharing_uuid: sharing_uuid || SecureRandom.uuid
    )
  end

  def disable_sharing!
    update!(
      sharing_settings: {
        'enabled' => false,
        'expiration' => nil,
        'expires_at' => nil
      }
    )
  end

  def share_notes?
    sharing_settings.try(:[], 'share_notes') == true
  end

  def share_photos?
    sharing_settings.try(:[], 'share_photos') == true
  end

  private

  def generate_sharing_uuid
    self.sharing_uuid ||= SecureRandom.uuid
  end
end
