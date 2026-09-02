# frozen_string_literal: true

module TeslaMate
  class Sync
    PAGE_SIZE = 100
    OVERLAP = 7.days

    class IncompleteError < TeslaMate::Client::Error; end

    def initialize(user)
      @user = user
      @settings = user.safe_settings
    end

    def call
      return { skipped: true } if @settings.teslamate_url.blank?

      cutoff = Time.current.utc
      failures = []
      counts = { cars: 0, drives: 0, points: 0, skipped_points: 0 }

      client.cars.each do |car|
        car_id = car['car_id']
        counts[:cars] += 1
        sync_car(car_id, cutoff, counts, failures)
      end

      raise IncompleteError, incomplete_message(failures) if failures.any?

      record_synced_at(cutoff)
      counts
    end

    private

    def client
      @client ||= TeslaMate::Client.new(
        @settings.teslamate_url,
        username: @settings.teslamate_username,
        password: @settings.teslamate_password,
        api_token: @settings.teslamate_api_token,
        skip_ssl_verification: @settings.teslamate_skip_ssl_verification
      )
    end

    def sync_car(car_id, cutoff, counts, failures)
      page = 1

      loop do
        result = client.drives(car_id, page: page, show: PAGE_SIZE,
                               start_date: sync_start, end_date: cutoff)
        result[:drives].each do |drive|
          sync_drive(car_id, drive['drive_id'], result[:units], counts, failures)
        end

        break if result[:drives].length < PAGE_SIZE

        page += 1
      end
    rescue TeslaMate::Client::Error => e
      failures << "car #{car_id}, page #{page}: #{e.message}"
    end

    def sync_drive(car_id, drive_id, list_units, counts, failures)
      result = client.drive(car_id, drive_id)
      unless result[:drive].key?('drive_details')
        raise TeslaMate::Client::Error, 'TeslaMateApi response did not contain drive details'
      end

      details = result[:drive]['drive_details']
      unless details.nil? || details.is_a?(Array)
        raise TeslaMate::Client::Error, 'TeslaMateApi response did not contain drive details'
      end

      payloads = Array(details).filter_map do |detail|
        point_payload(detail, car_id, drive_id, result[:units].presence || list_units)
      end
      counts[:skipped_points] += Array(details).length - payloads.length
      Points::Intake.call(user_id: @user.id, payloads: payloads.sort_by { |payload| payload[:timestamp] })
      counts[:drives] += 1
      counts[:points] += payloads.length
    rescue TeslaMate::Client::Error => e
      failures << "car #{car_id}, drive #{drive_id}: #{e.message}"
    end

    def point_payload(detail, car_id, drive_id, units)
      return unless detail.is_a?(Hash)

      latitude = coordinate(detail['latitude'], -90, 90)
      longitude = coordinate(detail['longitude'], -180, 180)
      timestamp = Time.iso8601(detail.fetch('date')).to_i
      return if latitude.nil? || longitude.nil?

      elevation = finite_number(detail['elevation'])
      {
        lonlat: "POINT(#{longitude} #{latitude})",
        timestamp: timestamp,
        altitude: elevation&.to_i,
        altitude_decimal: elevation,
        velocity: velocity(detail['speed'], units['unit_of_length']),
        battery: detail['usable_battery_level'] || detail['battery_level'],
        tracker_id: "teslamate-car-#{car_id}",
        external_track_id: "teslamate-drive-#{drive_id}",
        raw_data: detail.merge(
          'teslamate_car_id' => car_id,
          'teslamate_drive_id' => drive_id,
          'teslamate_detail_id' => detail['detail_id']
        )
      }
    rescue KeyError, ArgumentError, TypeError
      nil
    end

    def coordinate(value, minimum, maximum)
      number = finite_number(value)
      number if number&.between?(minimum, maximum)
    end

    def finite_number(value)
      return if value.nil?

      number = Float(value)
      number if number.finite?
    rescue ArgumentError, TypeError
      nil
    end

    def velocity(speed, unit)
      value = finite_number(speed)
      return if value.nil?

      case unit
      when 'km' then value / 3.6
      when 'mi' then value * 0.44704
      else
        raise TeslaMate::Client::Error, "unsupported length unit: #{unit.presence || 'missing'}"
      end
    end

    def sync_start
      value = @settings.settings['teslamate_last_synced_at']
      Time.iso8601(value) - OVERLAP if value.present?
    rescue ArgumentError
      nil
    end

    def record_synced_at(cutoff)
      User.where(id: @user.id).update_all(
        ["settings = jsonb_set(settings, '{teslamate_last_synced_at}', to_jsonb(?::text)), updated_at = ?",
         cutoff.iso8601, Time.current]
      )
    end

    def incomplete_message(failures)
      "TeslaMateApi sync incomplete: #{failures.join('; ')}"
    end
  end
end
