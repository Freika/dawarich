# frozen_string_literal: true

module AirTrail
  class ImportFlights
    def self.recalculate_stats(user_id, months)
      months.each { |year, month| Stats::CalculatingJob.perform_later(user_id, year, month) }
    end

    def self.months_for(pairs, zone)
      pairs.filter_map do |flight_date, departure_time|
        local_date = flight_date || departure_time&.in_time_zone(zone)&.to_date
        [local_date.year, local_date.month] if local_date
      end.uniq
    end

    def initialize(user)
      @user = user
      @settings = user.safe_settings
    end

    def call
      payload = fetch
      return { skipped: true } if payload.nil?

      result = JobOwnership.with_owner(ImportCommands::AIRTRAIL_FLIGHTS_KEY) { store(payload) }
      return result if result == :not_owner

      self.class.recalculate_stats(@user.id, result.delete(:months))
      result
    end

    def affected_months
      self.class.months_for(@user.flights.pluck(:flight_date, :departure_time), @user.timezone_iana)
    end

    private

    def fetch
      url = @settings.airtrail_url
      api_key = @settings.airtrail_api_key
      return if url.blank? || api_key.blank?

      AirTrail::Client.new(url, api_key, skip_ssl_verification: @settings.airtrail_skip_ssl_verification).flights
    end

    def store(payload)
      months_before_sync = affected_months
      counts = upsert(payload)
      record_synced_at
      counts.merge(months: months_before_sync | affected_months)
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
