# frozen_string_literal: true

module AirTrail
  class ImportFlights
    def initialize(user)
      @user = user
      @settings = user.safe_settings
    end

    def call
      url = @settings.airtrail_url
      api_key = @settings.airtrail_api_key
      return { skipped: true } if url.blank? || api_key.blank?

      payload = AirTrail::Client.new(
        url, api_key, skip_ssl_verification: @settings.airtrail_skip_ssl_verification
      ).flights

      counts = Flights::Upsert.new(@user, payload, mode: :replace).call
      record_synced_at
      counts
    end

    private

    def record_synced_at
      User.where(id: @user.id).update_all(
        ["settings = jsonb_set(settings, '{airtrail_last_synced_at}', to_jsonb(?::text)), updated_at = ?",
         Time.current.iso8601, Time.current]
      )
    end
  end
end
