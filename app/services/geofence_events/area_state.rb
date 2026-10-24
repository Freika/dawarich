# frozen_string_literal: true

module GeofenceEvents
  class AreaState
    def self.reconcile(area)
      store = StateStore.new(area.user)
      user_inside?(area) ? store.enter!(area.id) : store.leave!(area.id)
    rescue StateStore::Unavailable => e
      ExceptionReporter.call(e, 'Geofence state unavailable')
    end

    def self.forget(area)
      StateStore.new(area.user).leave!(area.id)
    rescue StateStore::Unavailable => e
      ExceptionReporter.call(e, 'Geofence state unavailable')
    end

    def self.user_inside?(area)
      latest = area.user.points.order(timestamp: :desc).limit(1).select(:id)
      Point.where(id: latest)
           .where('ST_DWithin(points.lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?, false)',
                  area.longitude.to_f, area.latitude.to_f, area.radius)
           .exists?
    end
    private_class_method :user_inside?
  end
end
