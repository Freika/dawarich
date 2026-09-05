# frozen_string_literal: true

module TeslaMate
  class Sync
    PAGE_SIZE = 100
    OVERLAP = 7.days
    MAX_REQUEST_FAILURES = 3

    class IncompleteError < TeslaMate::Client::Error; end

    def initialize(user)
      @user = user
      @settings = user.safe_settings
      @source_url = @settings.teslamate_url
      @recovering_processing = @settings.settings['teslamate_processing_pending'] &&
                               @settings.settings['teslamate_processing_pending_url'] == @source_url
    end

    def call
      return { skipped: true } if @settings.teslamate_url.blank?
      return { skipped: true } unless mark_processing_pending

      cutoff = Time.current.utc
      failures = []
      counts = { cars: 0, drives: 0, points: 0, skipped_points: 0 }
      import_completed = false

      begin
        client.cars.each do |car|
          if point_limit_reached?
            @quota_truncated = true
            break
          end

          car_id = car['car_id']
          counts[:cars] += 1
          sync_car(car_id, cutoff, counts, failures)
        end
        import_completed = true
      ensure
        finalize_historical_import
        clear_processing_pending if import_completed
      end

      raise IncompleteError, incomplete_message(failures) if failures.any?

      record_synced_at(cutoff) unless @quota_truncated
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
          if point_limit_reached?
            @quota_truncated = true
            break
          end

          next if sync_drive(car_id, drive['drive_id'], result[:units], counts, failures)

          stop_if_failure_budget_spent(failures)
        end

        if point_limit_reached?
          @quota_truncated = true if result[:drives].length == PAGE_SIZE
          break
        end
        break if result[:drives].length < PAGE_SIZE

        page += 1
      end
    rescue IncompleteError
      raise
    rescue TeslaMate::Client::Error => e
      failures << "car #{car_id}, page #{page}: #{e.message}"
      stop_if_failure_budget_spent(failures)
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

      valid_payloads = Array(details).filter_map do |detail|
        point_payload(detail, car_id, drive_id, result[:units].presence || list_units)
      end
      payloads = payloads_within_point_limit(valid_payloads)
      counts[:skipped_points] += Array(details).length - payloads.length
      rows = Points::Intake.call(
        user_id: @user.id,
        payloads: payloads.sort_by { |payload| payload[:timestamp] },
        mode: :bulk
      )
      consume_point_slots(rows)
      record_imported_range(rows)
      counts[:drives] += 1
      counts[:points] += payloads.length
      true
    rescue TeslaMate::Client::Error => e
      failures << "car #{car_id}, drive #{drive_id}: #{e.message}"
      false
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
      return unless @settings.settings['teslamate_last_synced_url'] == @source_url

      value = @settings.settings['teslamate_last_synced_at']
      Time.iso8601(value) - OVERLAP if value.present?
    rescue ArgumentError
      nil
    end

    def record_synced_at(cutoff)
      User.where(id: @user.id)
          .where("settings ->> 'teslamate_url' = ?", @source_url)
          .update_all(
            [
              "settings = jsonb_set(jsonb_set(settings, '{teslamate_last_synced_at}', " \
              "to_jsonb(?::text)), '{teslamate_last_synced_url}', to_jsonb(?::text)), updated_at = ?",
              cutoff.iso8601, @source_url, Time.current
            ]
          )
    end

    def record_imported_range(rows)
      relevant_rows = @recovering_processing ? rows : rows.select { |row| row['xmax'].to_i.zero? }
      timestamps = relevant_rows.map { |row| row['timestamp'].to_i }
      return if timestamps.empty?

      imported_months = timestamps.map do |timestamp|
        time = Time.zone.at(timestamp).in_time_zone(@user.timezone_iana)
        [time.year, time.month]
      end
      @imported_months = Array(@imported_months) | imported_months

      bounds = timestamps.minmax
      @imported_range ||= bounds
      @imported_range = [[@imported_range.first, bounds.first].min, [@imported_range.last, bounds.last].max]
    end

    def finalize_historical_import
      return unless @imported_range

      Points::AnomalyFilterJob.perform_later(@user.id, *@imported_range)
      Tracks::RealtimeDebouncer.new(@user.id).trigger
      Tracks::BackfillScheduler.new(@user.id, @imported_range).call
      @imported_months.each { |year, month| Stats::CalculatingJob.perform_later(@user.id, year, month) }
    end

    def payloads_within_point_limit(payloads)
      return payloads if DawarichSettings.self_hosted?

      existing_keys = existing_point_keys(payloads).index_with(true)
      slots = point_slots_remaining

      payloads.select do |payload|
        key = point_key(payload)
        next true if existing_keys[key]

        if slots.positive?
          existing_keys[key] = true
          slots -= 1
          true
        else
          @quota_truncated = true
          false
        end
      end
    end

    def existing_point_keys(payloads)
      timestamps = payloads.map { |payload| payload[:timestamp] }.uniq
      return [] if timestamps.empty?

      Point.where(user_id: @user.id, timestamp: timestamps)
           .pluck(:timestamp, Arel.sql('ST_X(lonlat::geometry)'), Arel.sql('ST_Y(lonlat::geometry)'))
           .map { |timestamp, lon, lat| [lon.to_f, lat.to_f, timestamp.to_i, @user.id] }
    end

    def point_key(payload)
      Point.dedup_key(payload.merge(user_id: @user.id))
    end

    def consume_point_slots(rows)
      return if DawarichSettings.self_hosted?

      inserted = rows.count { |row| row['xmax'].to_i.zero? }
      @point_slots_remaining = [point_slots_remaining - inserted, 0].max
    end

    def point_limit_reached?
      !DawarichSettings.self_hosted? && point_slots_remaining.zero?
    end

    def point_slots_remaining
      @point_slots_remaining ||= begin
        points_count = User.where(id: @user.id).pick(:points_count).to_i
        [@user.entitlements.points_limit - points_count, 0].max
      end
    end

    def mark_processing_pending
      User.where(id: @user.id)
          .where("settings ->> 'teslamate_url' = ?", @source_url)
          .update_all(
            [
              "settings = jsonb_set(jsonb_set(settings, '{teslamate_processing_pending}', 'true'::jsonb), " \
              "'{teslamate_processing_pending_url}', to_jsonb(?::text)), updated_at = ?",
              @source_url, Time.current
            ]
          ).positive?
    end

    def clear_processing_pending
      User.where(id: @user.id)
          .where("settings ->> 'teslamate_url' = ?", @source_url)
          .where("settings ->> 'teslamate_processing_pending_url' = ?", @source_url)
          .update_all(
            [
              "settings = jsonb_set(jsonb_set(settings, '{teslamate_processing_pending}', 'false'::jsonb), " \
              "'{teslamate_processing_pending_url}', 'null'::jsonb), updated_at = ?",
              Time.current
            ]
          )
    end

    def stop_if_failure_budget_spent(failures)
      return if failures.length < MAX_REQUEST_FAILURES

      raise IncompleteError, incomplete_message(failures)
    end

    def incomplete_message(failures)
      "TeslaMateApi sync incomplete: #{failures.join('; ')}"
    end
  end
end
