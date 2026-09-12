# frozen_string_literal: true

module Trek
  class Sync
    Result = Struct.new(:created, :updated, :unchanged, :stopped, keyword_init: true)

    def initialize(source, client: Client.new(source))
      @source = source
      @client = client
    end

    def call
      remote_trips = @client.trips.index_by { |trip| trip.fetch('id').to_s }
      result = Result.new(created: 0, updated: 0, unchanged: 0, stopped: 0)

      @source.trips.source_active.find_each do |managed_trip|
        remote = remote_trips[managed_trip.source_identifier]
        if remote.nil? || remote['archived']
          stop!(managed_trip)
          result.stopped += 1
          next
        end

        detail = @client.trip(managed_trip.source_identifier)
        if synchronize!(managed_trip, detail)
          result.updated += 1
        else
          result.unchanged += 1
        end
      end

      @source.update!(last_synced_at: Time.current, last_error: nil)
      result
    rescue Client::Error => e
      handle_error!(e)
      raise
    end

    # The selection UI calls this once for every trip the user chose. It is
    # intentionally separate from #call so a shared TREK trip is never pulled
    # merely because it appeared in the source's list response.
    def import!(identifier)
      detail = @client.trip(identifier)
      trip = @source.trips.find_or_initialize_by(source_identifier: identifier.to_s)
      created = trip.new_record?
      changed = synchronize!(trip, detail)
      @source.update!(last_synced_at: Time.current, last_error: nil)

      [trip, created, changed]
    rescue Client::Error => e
      handle_error!(e)
      raise
    end

    private

    def synchronize!(trip, payload)
      normalized = normalize(payload)
      digest = Digest::SHA256.hexdigest(JSON.generate(normalized))
      return false if trip.persisted? && trip.source_digest == digest

      Trip.transaction do
        trip.assign_attributes(
          user: @source.user,
          name: normalized.fetch('title').presence || 'Untitled TREK trip',
          started_at: day_start(normalized.fetch('start_date')),
          ended_at: day_end(normalized.fetch('end_date')),
          source_status: :active,
          source_digest: digest,
          source_synced_at: Time.current,
          source_snapshot: normalized
        )
        trip.save!
        replace_itinerary!(trip, normalized)
      end

      trip.enqueue_calculation_jobs unless trip.future?
      true
    end

    def replace_itinerary!(trip, payload)
      trip.planned_days.destroy_all
      trip.planned_reservations.destroy_all
      trip.planned_accommodations.destroy_all
      trip.planned_travellers.destroy_all

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
      canonicalize(payload.deep_stringify_keys)
    end

    def day_start(value)
      Time.zone.parse(value.to_s).beginning_of_day
    end

    def day_end(value)
      Time.zone.parse(value.to_s).end_of_day
    end

    def local_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)&.to_time
    rescue ArgumentError, TypeError
      nil
    end

    def local_datetime(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def stop!(trip)
      trip.update!(source_status: :stopped, source_synced_at: Time.current)
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
