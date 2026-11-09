# frozen_string_literal: true

# Expiring public links backed by the sharing_settings and sharing_uuid columns.
# Including models set DEFAULT_SHARING_EXPIRATION.
module PubliclyShareable
  extend ActiveSupport::Concern

  SHARING_DURATIONS = {
    '1h' => 1.hour, '12h' => 12.hours, '24h' => 24.hours, '1w' => 1.week, '1m' => 1.month
  }.freeze

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

  def enable_sharing!(expiration: self.class::DEFAULT_SHARING_EXPIRATION)
    expiration = '24h' unless SHARING_DURATIONS.key?(expiration)

    update!(
      sharing_settings: {
        'enabled' => true,
        'expiration' => expiration,
        'expires_at' => SHARING_DURATIONS.fetch(expiration).from_now.iso8601
      },
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
end
