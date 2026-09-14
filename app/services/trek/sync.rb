# frozen_string_literal: true

module Trek
  class Sync
    Result = Struct.new(:created, :updated, :unchanged, :stopped, :more, :next_cursor, keyword_init: true)

    def initialize(source, client: Client.new(source))
      @source = source
      @client = client
    end

    def call(limit: nil, after_id: nil)
      remote_trips = @client.trips.index_by { |trip| trip.fetch('id').to_s }
      result = Result.new(created: 0, updated: 0, unchanged: 0, stopped: 0, more: false)
      selection_token = @source.selection_token
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
      end

      remaining_trips = @source.trips.source_active.where('id > ?', result.next_cursor || after_id || 0)
      result.more = limit.present? && remaining_trips.exists?
      @source.update!(last_synced_at: Time.current, last_error: nil) unless result.more
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
        replace_itinerary!(trip, normalized)
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

    def replace_itinerary!(trip, payload)
      trip.planned_days.destroy_all
      trip.planned_reservations.destroy_all
      trip.planned_accommodations.destroy_all
      trip.planned_travellers.destroy_all
      trip.planned_unplanned_places.destroy_all

      Array(payload['days']).each do |day|
        planned_day = trip.planned_days.create!(
          date: day.fetch('date'),
          position: day.fetch('day_number'),
          title: day['title'],
          notes: day['notes']
        )
        Array(day['places']).each_with_index do |stop, index|
          planned_day.planned_stops.create!(stop_attributes(stop, index))
        end
        Array(day['day_notes']).each_with_index do |note, index|
          planned_day.planned_day_notes.create!(
            position: index,
            noted_at: local_time(note['time']),
            body: note.fetch('text')
          )
        end
        Array(day['reservations']).each do |reservation|
          trip.planned_reservations.create!(reservation_attributes(reservation, planned_day))
        end
      end

      Array(payload['unscheduled_reservations']).each do |reservation|
        trip.planned_reservations.create!(reservation_attributes(reservation, nil))
      end
      Array(payload['accommodations']).each do |accommodation|
        trip.planned_accommodations.create!(accommodation_attributes(accommodation))
      end
      Array(payload['travellers']).each do |traveller|
        trip.planned_travellers.create!(name: traveller.fetch('name'), owner: traveller['owner'] == true)
      end
      Array(payload['unplanned_places']).each_with_index do |place, index|
        trip.planned_unplanned_places.create!(stop_attributes(place, index))
      end
    end

    def stop_attributes(stop, position)
      {
        position: position,
        name: stop.fetch('name'), address: stop['address'], latitude: stop['lat'], longitude: stop['lng'],
        starts_at: local_time(stop['time']), ends_at: local_time(stop['end_time']),
        duration_minutes: stop['duration_minutes'], category: stop['category'],
        transport_mode: stop['transport_mode'], notes: stop['notes']
      }
    end

    def reservation_attributes(reservation, planned_day)
      {
        planned_day: planned_day, reservation_type: reservation['type'], title: reservation.fetch('title'),
        location: reservation['location'], starts_at: local_datetime(reservation['time']),
        ends_at: local_datetime(reservation['end_time']), status: reservation['status'], notes: reservation['notes']
      }
    end

    def accommodation_attributes(accommodation)
      {
        name: accommodation.fetch('name'), address: accommodation['address'],
        latitude: accommodation['lat'], longitude: accommodation['lng'],
        starts_on: accommodation['start_date'], ends_on: accommodation['end_date'],
        check_in_at: local_time(accommodation['check_in']), check_out_at: local_time(accommodation['check_out']),
        notes: accommodation['notes']
      }
    end

    def normalize(payload)
      normalized = payload.deep_stringify_keys
      validate_payload!(normalized)

      canonicalize(normalized)
    end

    def validate_payload!(payload)
      validate_required_fields!(payload, %w[start_date end_date], 'trip')
      trip_start = validate_date!(payload['start_date'], 'trip start_date')
      trip_end = validate_date!(payload['end_date'], 'trip end_date')
      invalid_payload!('trip end_date precedes start_date') if trip_end < trip_start

      day_dates = collection!(payload, 'days').map do |day|
        validate_required_fields!(day, %w[date day_number], 'day')
        day_date = validate_date!(day['date'], 'day date')
        validate_integer!(day['day_number'], 'day number')
        validate_named_collection!(day, 'places', 'place')
        validate_named_collection!(day, 'day_notes', 'day note', field: 'text')
        validate_named_collection!(day, 'reservations', 'reservation', field: 'title')
        day_date.to_date
      end
      invalid_payload!('days contain duplicate dates') if day_dates.uniq.length != day_dates.length

      validate_named_collection!(payload, 'unscheduled_reservations', 'reservation', field: 'title')
      validate_named_collection!(payload, 'accommodations', 'accommodation')
      validate_named_collection!(payload, 'travellers', 'traveller')
      validate_named_collection!(payload, 'unplanned_places', 'unplanned place')
    end

    def validate_named_collection!(payload, collection_name, item_name, field: 'name')
      collection!(payload, collection_name).each do |item|
        validate_required_fields!(item, [field], item_name)
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
    end

    def validate_date!(value, field)
      parsed = source_time_zone.parse(value.to_s)
      invalid_payload!("#{field} is invalid") unless parsed

      parsed
    rescue ArgumentError, TypeError
      invalid_payload!("#{field} is invalid")
    end

    def validate_integer!(value, field)
      Integer(value)
    rescue ArgumentError, TypeError
      invalid_payload!("#{field} is invalid")
    end

    def invalid_payload!(message)
      raise Client::Error, "TREK trip response is invalid: #{message}"
    end

    def day_start(value)
      source_time_zone.parse(value.to_s).beginning_of_day
    end

    def day_end(value)
      source_time_zone.parse(value.to_s).end_of_day
    end

    def local_time(value)
      return if value.blank?

      source_time_zone.parse(value.to_s)&.to_time
    rescue ArgumentError, TypeError
      nil
    end

    def local_datetime(value)
      return if value.blank?

      source_time_zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
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
