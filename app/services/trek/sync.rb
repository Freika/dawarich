# frozen_string_literal: true

module Trek
  class Sync
    class UndatedTripError < StandardError; end
    # A payload this source will keep sending; retrying it never helps.
    class InvalidPayloadError < Client::Error; end

    Result = Struct.new(:created, :updated, :unchanged, :stopped, :more, :next_cursor, keyword_init: true)

    def initialize(source, client: Client.new(source))
      @source = source
      @client = client
    end

    def call(limit: nil, after_id: nil)
      remote_trips = @client.trips.index_by { |trip| trip.fetch('id').to_s }
      result = Result.new(created: 0, updated: 0, unchanged: 0, stopped: 0, more: false)
      selection_token = @source.selection_token
      trip_error = nil
      managed_trips = @source.trips.source_active.order(:id)
      managed_trips = managed_trips.where('id > ?', after_id) if after_id
      managed_trips = managed_trips.limit(limit) if limit

      managed_trips.each do |managed_trip|
        result.next_cursor = managed_trip.id
        remote = remote_trips[managed_trip.source_identifier]
        if remote.nil? || remote['archived']
          result.stopped += 1 if stop_if_current!(managed_trip, selection_token)
          next
        end

        detail = @client.trip(managed_trip.source_identifier)
        changed = synchronize_if_current!(managed_trip, detail, selection_token)
        next if changed.nil?

        if changed
          result.updated += 1
        else
          result.unchanged += 1
        end
        enqueue_calculation_if_needed!(managed_trip, force: changed)
      rescue UndatedTripError, InvalidPayloadError => e
        trip_error = e.message
        result.stopped += 1 if stop_if_current!(managed_trip, selection_token)
      rescue Client::Error => e
        raise unless e.status == 404

        trip_error = e.message
        result.stopped += 1 if stop_if_current!(managed_trip, selection_token)
      end

      remaining_trips = @source.trips.source_active.where('id > ?', result.next_cursor || after_id || 0)
      result.more = limit.present? && remaining_trips.exists?
      @source.update!(last_synced_at: Time.current, last_error: trip_error) unless result.more
      result
    rescue Client::Error => e
      handle_error!(e)
      raise
    end

    # The selection UI calls this once for every trip the user chose. It is
    # intentionally separate from #call so a shared TREK trip is never pulled
    # merely because it appeared in the source's list response.
    def import!(identifier)
      detail = fetch_trip(identifier)
      import_payload!(identifier, detail)
    rescue Client::Error => e
      handle_error!(e)
      raise
    end

    def fetch_trip(identifier)
      @client.trip(identifier)
    end

    def import_payload!(identifier, detail)
      normalized = normalize(detail)
      trip = @source.trips.find_or_initialize_by(source_identifier: identifier.to_s)
      created = trip.new_record?
      changed = synchronize_normalized!(trip, normalized)
      enqueue_calculation_if_needed!(trip, force: changed)
      @source.update!(last_synced_at: Time.current, last_error: nil)

      [trip, created, changed]
    end

    # ImportTripsJob fetches details in rate-limited batches, so it cannot use
    # #import!'s rescue block. Keep its source errors consistent with the
    # regular synchronizer nevertheless.
    def record_error!(error)
      handle_error!(error)
    end

    private

    def synchronize!(trip, payload)
      synchronize_normalized!(trip, normalize(payload))
    end

    def synchronize_normalized!(trip, normalized)
      digest = Digest::SHA256.hexdigest(JSON.generate(normalized))
      if trip.persisted? && trip.source_digest == digest
        trip.update!(source_status: :active, source_synced_at: Time.current) if trip.source_stopped?
        return false
      end

      previous_snapshot = trip.source_snapshot
      Trip.transaction do
        trip.assign_attributes(
          user: @source.user,
          name: normalized['title'].presence || 'Untitled TREK trip',
          started_at: day_start(normalized.fetch('start_date')),
          ended_at: day_end(normalized.fetch('end_date')),
          source_status: :active,
          source_digest: digest,
          source_synced_at: Time.current,
          source_snapshot: normalized
        )
        trip.skip_calculation_enqueue = true
        trip.save!
        Itinerary.new(trip, normalized, time_zone: source_time_zone).call
        DayNotes.new(trip, previous_snapshot).call
      end

      true
    end

    def synchronize_if_current!(trip, payload, selection_token)
      @source.with_lock do
        if current_selection?(selection_token)
          trip.reload
          synchronize!(trip, payload) if trip.source_active?
        end
      end
    end

    def normalize(payload)
      normalized = payload.deep_stringify_keys
      validate_payload!(normalized)

      canonicalize(normalized)
    end

    def validate_payload!(payload)
      validate_required_keys!(payload, %w[start_date end_date], 'trip')
      if payload['start_date'].nil? || payload['end_date'].nil?
        raise UndatedTripError, 'TREK trip needs start and end dates before it can be imported'
      end

      validate_required_fields!(payload, %w[start_date end_date], 'trip')
      trip_start = validate_date!(payload['start_date'], 'trip start_date')
      trip_end = validate_date!(payload['end_date'], 'trip end_date')
      invalid_payload!('trip end_date precedes start_date') if trip_end < trip_start

      day_dates = collection!(payload, 'days').map do |day|
        validate_required_fields!(day, %w[date day_number], 'day')
        day_date = validate_date!(day['date'], 'day date')
        invalid_payload!('day date falls outside the trip range') if day_date < trip_start || day_date > trip_end
        validate_positive_integer!(day['day_number'], 'day number')
        validate_places!(day, 'places', 'place')
        validate_named_collection!(day, 'day_notes', 'day note', field: 'text')
        validate_named_collection!(day, 'reservations', 'reservation', field: nil)
        day_date.to_date
      end
      invalid_payload!('days contain duplicate dates') if day_dates.uniq.length != day_dates.length

      validate_named_collection!(payload, 'unscheduled_reservations', 'reservation', field: nil)
      collection!(payload, 'accommodations').each do |accommodation|
        invalid_payload!('accommodation must be an object') unless accommodation.is_a?(Hash)
        validate_coordinates!(accommodation, 'accommodation')
        accommodation_start = validate_optional_date!(accommodation['start_date'], 'accommodation start_date')
        accommodation_end = validate_optional_date!(accommodation['end_date'], 'accommodation end_date')
        if accommodation_start && accommodation_end && accommodation_end < accommodation_start
          invalid_payload!('accommodation end_date precedes start_date')
        end
      end
      validate_named_collection!(payload, 'travellers', 'traveller')
      validate_places!(payload, 'unplanned_places', 'unplanned place')
    end

    def validate_places!(payload, collection_name, item_name)
      collection!(payload, collection_name).each do |place|
        validate_required_fields!(place, ['name'], item_name)
        validate_coordinates!(place, item_name)
        validate_optional_nonnegative_integer!(place['duration_minutes'], "#{item_name} duration_minutes")
      end
    end

    def validate_named_collection!(payload, collection_name, item_name, field: 'name')
      collection!(payload, collection_name).each do |item|
        validate_required_fields!(item, Array(field), item_name)
      end
    end

    def collection!(payload, field)
      value = payload[field]
      return [] if value.nil?
      return value if value.is_a?(Array)

      invalid_payload!("#{field} must be an array")
    end

    def validate_required_fields!(payload, fields, object_name)
      invalid_payload!("#{object_name} must be an object") unless payload.is_a?(Hash)

      missing_fields = fields.select { |field| payload[field].blank? }
      invalid_payload!("#{object_name} is missing required fields: #{missing_fields.join(', ')}") if missing_fields.any?
      invalid_payload!("#{object_name} contains invalid fields") unless fields.all? { |field| scalar?(payload[field]) }
    end

    def validate_required_keys!(payload, fields, object_name)
      invalid_payload!("#{object_name} must be an object") unless payload.is_a?(Hash)

      missing_keys = fields.reject { |field| payload.key?(field) }
      invalid_payload!("#{object_name} is missing required fields: #{missing_keys.join(', ')}") if missing_keys.any?
    end

    def validate_date!(value, field)
      Date.iso8601(value.to_s)
    rescue Date::Error, TypeError
      invalid_payload!("#{field} is invalid")
    end

    def validate_optional_date!(value, field)
      validate_date!(value, field) unless value.nil?
    end

    def validate_coordinates!(payload, object_name)
      latitude = payload['lat']
      longitude = payload['lng']
      return if latitude.nil? && longitude.nil?

      invalid_payload!("#{object_name} coordinates are incomplete") if latitude.nil? || longitude.nil?

      validate_number_in_range!(latitude, -90..90, "#{object_name} latitude")
      validate_number_in_range!(longitude, -180..180, "#{object_name} longitude")
    end

    def validate_optional_nonnegative_integer!(value, field)
      return if value.nil?

      invalid_payload!("#{field} is invalid") if validate_integer!(value, field).negative?
    end

    def validate_positive_integer!(value, field)
      invalid_payload!("#{field} is invalid") unless validate_integer!(value, field).positive?
    end

    def validate_integer!(value, field)
      return value if value.is_a?(Integer)
      return Integer(value, 10) if value.is_a?(String) && value.match?(/\A[+-]?\d+\z/)

      invalid_payload!("#{field} is invalid")
    end

    def scalar?(value)
      value.is_a?(String) || value.is_a?(Numeric)
    end

    def validate_number_in_range!(value, range, field)
      number = Float(value)
      invalid_payload!("#{field} is invalid") unless number.finite? && range.cover?(number)
    rescue ArgumentError, TypeError
      invalid_payload!("#{field} is invalid")
    end

    def invalid_payload!(message)
      raise InvalidPayloadError, "TREK trip response is invalid: #{message}"
    end

    def day_start(value)
      source_time_zone.parse(value.to_s).beginning_of_day
    end

    def day_end(value)
      source_time_zone.parse(value.to_s).end_of_day
    end

    def stop_if_current!(trip, selection_token)
      @source.with_lock do
        if current_selection?(selection_token)
          trip.reload
          if trip.source_active?
            stop!(trip)
            true
          else
            false
          end
        else
          false
        end
      end
    end

    def stop!(trip)
      trip.update!(source_status: :stopped, source_synced_at: Time.current)
    end

    def current_selection?(selection_token)
      @source.selection_token == selection_token && !@source.importing?
    end

    def enqueue_calculation_if_needed!(trip, force: false)
      return if trip.started_at > Time.current
      return unless force || trip.path.blank? || trip.distance.blank? || trip.visited_countries.blank?

      trip.enqueue_calculation_jobs
    end

    def source_time_zone
      @source_time_zone ||= Time.find_zone(@source.user.timezone) || Time.zone
    end

    def canonicalize(value)
      case value
      when Hash
        value.keys.sort.index_with { |key| canonicalize(value[key]) }
      when Array
        value.map { |item| canonicalize(item) }
      else
        value
      end
    end

    def handle_error!(error)
      attributes = { last_error: error.message }
      attributes[:status] = :disabled if error.status == 401
      @source.update!(attributes)
    end
  end
end
