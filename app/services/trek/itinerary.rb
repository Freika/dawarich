# frozen_string_literal: true

module Trek
  class Itinerary
    def initialize(trip, payload, time_zone: trip.user.timezone)
      @trip = trip
      @payload = payload
      @source_time_zone = Time.find_zone(time_zone) || Time.zone
    end

    def call
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

    private

    attr_reader :trip, :payload, :source_time_zone

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
        planned_day: planned_day, reservation_type: reservation['type'],
        title: reservation['title'].presence || 'Reservation',
        location: reservation['location'], starts_at: local_datetime(reservation['time'], date: planned_day&.date),
        ends_at: local_datetime(reservation['end_time'], date: planned_day&.date),
        status: reservation['status'], notes: reservation['notes']
      }
    end

    def accommodation_attributes(accommodation)
      {
        name: accommodation['name'].presence || 'Accommodation', address: accommodation['address'],
        latitude: accommodation['lat'], longitude: accommodation['lng'],
        starts_on: accommodation['start_date'], ends_on: accommodation['end_date'],
        check_in_at: local_time(accommodation['check_in']), check_out_at: local_time(accommodation['check_out']),
        notes: accommodation['notes']
      }
    end

    def local_time(value)
      return if value.blank?

      source_time_zone.parse(value.to_s)&.strftime('%H:%M:%S')
    rescue ArgumentError, TypeError
      nil
    end

    def local_datetime(value, date: nil)
      return if value.blank?

      value = "#{date} #{value}" if date && time_only?(value)
      source_time_zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def time_only?(value)
      value.to_s.match?(/\A\d{1,2}:\d{2}(?::\d{2})?\z/)
    end
  end
end
