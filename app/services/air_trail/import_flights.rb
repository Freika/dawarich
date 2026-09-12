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

      months_before_sync = affected_months
      attrs = Array(payload).map { |raw| AirTrail::FlightMapper.new(raw).attributes }
      counts = Flights::Upsert.new(@user, attrs, mode: :replace).call
      record_synced_at
      recalculate_stats(months_before_sync | affected_months)
      counts
    end

    private

    def affected_months
      @user.flights.pluck(:flight_date, :departure_time).filter_map do |flight_date, departure_time|
        local_date = flight_date || departure_time&.in_time_zone(@user.timezone_iana)&.to_date
        [local_date.year, local_date.month] if local_date
      end.uniq
    end

    def recalculate_stats(months)
      months.each { |year, month| Stats::CalculatingJob.perform_later(@user.id, year, month) }
    end

    def record_synced_at
      User.where(id: @user.id).update_all(
        ["settings = jsonb_set(COALESCE(settings, '{}'::jsonb), '{airtrail_last_synced_at}', to_jsonb(?::text)), updated_at = ?",
         Time.current.iso8601, Time.current]
      )
    end
  end
end
