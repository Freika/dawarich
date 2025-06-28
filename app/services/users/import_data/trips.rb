# frozen_string_literal: true

class Users::ImportData::Trips
  def initialize(user, trips_data)
    @user = user
    @trips_data = trips_data
  end

  def call
    return 0 unless trips_data.is_a?(Array)

    Rails.logger.info "Importing #{trips_data.size} trips for user: #{user.email}"

    trips_created = 0

    trips_data.each do |trip_data|
      next unless trip_data.is_a?(Hash)

      # Check if trip already exists (match by name and timestamps)
      existing_trip = user.trips.find_by(
        name: trip_data['name'],
        started_at: trip_data['started_at'],
        ended_at: trip_data['ended_at']
      )

      if existing_trip
        Rails.logger.debug "Trip already exists: #{trip_data['name']}"
        next
      end

      # Create new trip
      trip_attributes = trip_data.except('created_at', 'updated_at')
      trip = user.trips.create!(trip_attributes)
      trips_created += 1

      Rails.logger.debug "Created trip: #{trip.name}"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create trip: #{e.message}"
      next
    end

    Rails.logger.info "Trips import completed. Created: #{trips_created}"
    trips_created
  end

  private

  attr_reader :user, :trips_data
end
