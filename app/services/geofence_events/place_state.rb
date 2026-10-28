# frozen_string_literal: true

module GeofenceEvents
  class PlaceState
    def self.reconcile(place)
      store = StateStore.new(place.user)
      user_inside?(place) ? store.enter!(place.id) : store.leave!(place.id)
    rescue StateStore::Unavailable => e
      ExceptionReporter.call(e, 'Geofence state unavailable')
    end

    def self.forget(place)
      StateStore.new(place.user).leave!(place.id)
    rescue StateStore::Unavailable => e
      ExceptionReporter.call(e, 'Geofence state unavailable')
    end

    def self.user_inside?(place)
      latest = place.user.points.order(timestamp: :desc).limit(1).select(:id)
      Point.where(id: latest)
           .where('ST_DWithin(points.lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?, false)',
                  place.lon, place.lat, place.visit_radius)
           .exists?
    end
    private_class_method :user_inside?
  end
end
