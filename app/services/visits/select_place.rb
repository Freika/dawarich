# frozen_string_literal: true

module Visits
  class SelectPlace
    include AdvisoryLockable

    PROXIMITY_METERS = 50

    def initialize(user:, visit:, photon:)
      @user = user
      @visit = visit
      @photon = photon.respond_to?(:with_indifferent_access) ? photon.with_indifferent_access : photon
    end

    def call
      with_dedup_lock do
        place = find_by_name_and_proximity || create_place
        place.update!(name_locked_at: Time.current) unless place.name_locked?
        # Picking a place is asserting the visit — no separate confirm step.
        @visit.update!(place_id: place.id, name: place.name, status: :confirmed)
        place
      end
    end

    private

    def with_dedup_lock(&block)
      return block.call unless advisory_locks_enabled?

      ident = @photon[:osm_id].presence || "#{@photon[:name]}:#{@photon[:latitude]}:#{@photon[:longitude]}"
      ActiveRecord::Base.with_advisory_lock("select_place:#{@user.id}:#{ident}", &block)
    end

    def find_by_name_and_proximity
      name = @photon[:name]
      lat = @photon[:latitude].to_f
      lon = @photon[:longitude].to_f
      return nil if name.blank?

      @user.places
           .where(name: name)
           .where(
             'ST_DWithin(lonlat::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
             lon, lat, PROXIMITY_METERS
           )
           .first
    end

    def create_place
      lat = @photon[:latitude].to_f
      lon = @photon[:longitude].to_f

      @user.places.create!(
        name: @photon[:name],
        latitude: lat,
        longitude: lon,
        lonlat: "POINT(#{lon} #{lat})",
        city: @photon[:city],
        country: @photon[:country],
        geodata: DawarichSettings.store_geodata? ? (@photon[:geodata] || {}) : {},
        source: :photon,
        user_named: true
      )
    end
  end
end
