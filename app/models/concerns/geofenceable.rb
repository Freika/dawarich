# frozen_string_literal: true

module Geofenceable
  extend ActiveSupport::Concern

  included do
    has_many :geofence_events, dependent: :nullify

    before_destroy :snapshot_geofence_event_names, prepend: true

    scope :geofences, -> { where(geofence: true) }

    after_commit :reconcile_geofence_state, on: %i[create update], if: :geofence_boundary_changed?
    after_commit :release_geofence, on: %i[update destroy], if: :geofence_released?
  end

  private

  def snapshot_geofence_event_names
    geofence_events.update_all(place_name: name)
  end

  def geofence_boundary_changed?
    return false unless geofence?

    previously_new_record? || saved_change_to_geofence? ||
      saved_change_to_lonlat? || saved_change_to_visit_radius?
  end

  def geofence_released?
    destroyed? ? geofence? : saved_change_to_geofence?(from: true, to: false)
  end

  def reconcile_geofence_state
    GeofenceEvents::PlaceState.reconcile(self)
  end

  def release_geofence
    GeofenceEvents::PlaceState.forget(self)
    Webhook.where(user_id:).where('? = ANY(place_ids)', id).update_all(
      [<<~SQL.squish, id, id]
        active = active AND cardinality(array_remove(place_ids, ?)) > 0,
        place_ids = array_remove(place_ids, ?)
      SQL
    )
  end
end
