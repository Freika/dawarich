# frozen_string_literal: true

module Visits
  class Create
    attr_reader :user, :params, :errors, :visit

    def initialize(user, params)
      @user = user
      @params = params.respond_to?(:with_indifferent_access) ? params.with_indifferent_access : params
      @visit = nil
      @errors = nil
    end

    def call
      ActiveRecord::Base.transaction do
        place = find_or_create_place
        return false unless place

        visit = create_visit(place)
        visit
      end
    rescue ActiveRecord::RecordInvalid => e
      ExceptionReporter.call(e, "Failed to create visit: #{e.message}")

      @errors = "Failed to create visit: #{e.message}"

      false
    rescue StandardError => e
      ExceptionReporter.call(e, "Failed to create visit: #{e.message}")

      @errors = "Failed to create visit: #{e.message}"
      false
    end

    private

    def find_or_create_place
      existing_place = find_existing_place

      return existing_place if existing_place

      create_new_place
    end

    def find_existing_place
      Place.joins("JOIN visits ON places.id = visits.place_id")
           .where(visits: { user: user })
           .where(
             "ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326), ?)",
             params[:longitude].to_f, params[:latitude].to_f, 0.001 # approximately 100 meters
           ).first
    end

    def create_new_place
      place_name = params[:name]
      lat_f = params[:latitude].to_f
      lon_f = params[:longitude].to_f

      place = Place.create!(
        name: place_name,
        latitude: lat_f,
        longitude: lon_f,
        lonlat: "POINT(#{lon_f} #{lat_f})",
        source: :manual
      )

      place
    rescue StandardError => e
      ExceptionReporter.call(e, "Failed to create place: #{e.message}")
      nil
    end

    def create_visit(place)
      started_at = Time.zone.parse(params[:started_at])
      ended_at = Time.zone.parse(params[:ended_at])
      duration_minutes = ((ended_at - started_at) / 60).to_i

      @visit = user.visits.create!(
        name: params[:name],
        place: place,
        started_at: started_at,
        ended_at: ended_at,
        duration: duration_minutes,
        status: :confirmed
      )

      @visit
    end
  end
end
