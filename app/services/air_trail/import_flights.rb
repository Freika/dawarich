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
      counts = upsert(payload)
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

    def upsert(payload)
      created = 0
      updated = 0
      seen = []

      Flight.transaction do
        payload.each do |raw|
          attrs = AirTrail::FlightMapper.new(raw).attributes
          seen << attrs[:external_id]

          begin
            Flight.transaction(requires_new: true) do
              flight = @user.flights.find_or_initialize_by(external_id: attrs[:external_id])
              was_new = flight.new_record?
              flight.update!(attrs)
              was_new ? created += 1 : updated += 1
            end
          rescue ActiveRecord::RecordNotUnique
            updated += 1 if @user.flights.find_by(external_id: attrs[:external_id])&.update!(attrs)
          end
        end

        deleted = @user.flights.where.not(external_id: seen).delete_all
        { created: created, updated: updated, deleted: deleted }
      end
    end

    def record_synced_at
      User.where(id: @user.id).update_all(
        ["settings = jsonb_set(settings, '{airtrail_last_synced_at}', to_jsonb(?::text)), updated_at = ?",
         Time.current.iso8601, Time.current]
      )
    end
  end
end
