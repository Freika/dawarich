# frozen_string_literal: true

module Visits
  class Create
    attr_reader :user, :params, :errors, :visit

    def initialize(user, params, report_exceptions: true)
      @user = user
      @params = params.respond_to?(:with_indifferent_access) ? params.with_indifferent_access : params
      @report_exceptions = report_exceptions
      @visit = nil
      @errors = nil
      @duplicate = false
      @created_place = nil
    end

    def call
      return false unless timestamps_usable?
      return false unless coordinates_usable?

      result = ActiveRecord::Base.transaction do
        place = find_or_create_place
        return false unless place

        create_visit(place)
      end

      enqueue_name_fetching

      result
    rescue ActiveRecord::RecordNotUnique
      @duplicate = true
      @visit = existing_visit
      @visit.update!(deleted_at: nil, status: :confirmed) if @visit && revivable?(@visit)
      @errors = 'Failed to create visit: duplicate visit' unless @visit

      @visit || false
    rescue ActiveRecord::RecordInvalid => e
      report_exception(e, "Failed to create visit: #{e.message}")

      @errors = "Failed to create visit: #{e.message}"

      false
    rescue StandardError => e
      report_exception(e, "Failed to create visit: #{e.message}")

      @errors = "Failed to create visit: #{e.message}"
      false
    end

    def duplicate?
      @duplicate
    end

    private

    def report_exception(error, message)
      return unless @report_exceptions

      ExceptionReporter.call(error, message)
    end

    def revivable?(visit)
      return false if suggested?

      visit.soft_deleted? || visit.declined?
    end

    def coordinates_usable?
      if latitude.nil? || longitude.nil?
        @errors = 'Failed to create visit: invalid coordinates'
        return false
      end

      unless latitude.between?(-90, 90) && longitude.between?(-180, 180)
        @errors = 'Failed to create visit: coordinates out of range'
        return false
      end

      true
    end

    def latitude
      return @latitude if defined?(@latitude)

      @latitude = parse_coordinate(params[:latitude])
    end

    def longitude
      return @longitude if defined?(@longitude)

      @longitude = parse_coordinate(params[:longitude])
    end

    def parse_coordinate(value)
      return nil if value.blank?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def timestamps_usable?
      if started_at.nil? || ended_at.nil?
        @errors = 'Failed to create visit: invalid timestamps'
        return false
      end

      if ended_at < started_at
        @errors = 'Failed to create visit: ended_at is before started_at'
        return false
      end

      true
    end

    def started_at
      return @started_at if defined?(@started_at)

      @started_at = parse_time(params[:started_at])
    end

    def ended_at
      return @ended_at if defined?(@ended_at)

      @ended_at = parse_time(params[:ended_at])
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def find_or_create_place
      existing_place = find_existing_place

      return existing_place if existing_place

      create_new_place
    end

    def existing_visit
      place = find_existing_place
      return nil unless place

      user.visits.find_by(place_id: place.id, started_at: started_at)
    end

    def find_existing_place
      Place.joins('JOIN visits ON places.id = visits.place_id')
           .where(user: user)
           .where(visits: { user: user })
           .where(
             'ST_DWithin(places.lonlat::geography, ' \
             'ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
             longitude, latitude, 100
           ).first
    end

    def create_new_place
      @created_place = Place.create!(
        user: user,
        name: params[:name],
        latitude: latitude,
        longitude: longitude,
        lonlat: "POINT(#{longitude} #{latitude})",
        source: :manual,
        user_named: !suggested?,
        machine_named: suggested?
      )
    rescue ActiveRecord::RecordInvalid => e
      report_exception(e, "Failed to create place: #{e.message}")
      nil
    end

    def enqueue_name_fetching
      return unless suggested?
      return if @created_place.nil?
      return unless Geocoding::Config.for(user).enabled?

      Places::NameFetchingJob.perform_later(@created_place.id)
    rescue StandardError => e
      report_exception(e, "Failed to enqueue place name fetching: #{e.message}")
    end

    def suggested?
      params[:status].to_s == 'suggested'
    end

    def create_visit(place)
      duration_minutes = ((ended_at - started_at) / 60).to_i

      @visit = user.visits.create!(
        name: params[:name].presence || place.name,
        place: place,
        started_at: started_at,
        ended_at: ended_at,
        duration: duration_minutes,
        status: params[:status].presence || :confirmed
      )

      @visit
    end
  end
end
