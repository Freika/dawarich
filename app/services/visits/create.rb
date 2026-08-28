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
    rescue ActiveRecord::RecordNotUnique
      @visit = existing_visit
      # Re-creating a visit over its own tombstone (or an old decline) is an
      # explicit undo: revive the row instead of returning it still hidden.
      @visit.update!(deleted_at: nil, status: :confirmed) if @visit && (@visit.soft_deleted? || @visit.declined?)
      @errors = 'Failed to create visit: duplicate visit' unless @visit

      @visit || false
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

    def existing_visit
      place = find_existing_place
      return nil unless place

      user.visits.find_by(place_id: place.id, started_at: Time.zone.parse(params[:started_at]))
    end

    def find_existing_place
      Place.joins('JOIN visits ON places.id = visits.place_id')
           .where(user: user)
           .where(visits: { user: user })
           .where(
             'ST_DWithin(places.lonlat::geography, ' \
             'ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
             params[:longitude].to_f, params[:latitude].to_f, 100
           ).first
    end

    def create_new_place
      place_name = params[:name]
      lat_f = params[:latitude].to_f
      lon_f = params[:longitude].to_f

      Place.create!(
        user: user,
        name: place_name,
        latitude: lat_f,
        longitude: lon_f,
        lonlat: "POINT(#{lon_f} #{lat_f})",
        source: :manual,
        user_named: true
      )
    rescue ActiveRecord::RecordInvalid => e
      ExceptionReporter.call(e, "Failed to create place: #{e.message}")
      nil
    end

    def create_visit(place)
      started_at = Time.zone.parse(params[:started_at])
      ended_at = Time.zone.parse(params[:ended_at])
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
