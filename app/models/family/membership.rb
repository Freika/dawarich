# frozen_string_literal: true

class Family::Membership < ApplicationRecord
  self.table_name = 'family_memberships'

  belongs_to :family
  belongs_to :user

  validates :user_id, presence: true, uniqueness: true
  validates :role, presence: true

  enum :role, { owner: 0, member: 1 }

  FAMILY_MAP_LAYER = 'Family Members'

  after_create :clear_family_cache
  after_create :enable_family_map_layer
  after_update :clear_family_cache
  after_destroy :clear_family_cache
  after_destroy :cleanup_on_departure

  private

  def clear_family_cache
    family.clear_member_cache!
  end

  # A new member should see the family on the map without hunting for the toggle.
  def enable_family_map_layer
    settings = user.settings || {}
    layers = Array(settings['enabled_map_layers'] || Users::SafeSettings::DEFAULT_VALUES['enabled_map_layers'])
    return if layers.include?(FAMILY_MAP_LAYER)

    user.update_columns(settings: settings.merge('enabled_map_layers' => layers + [FAMILY_MAP_LAYER]))
  end

  # Without a family the layer has nothing to show and the map would report a failed load.
  def disable_family_map_layer
    settings = user.settings || {}
    layers = Array(settings['enabled_map_layers'])
    return unless layers.include?(FAMILY_MAP_LAYER)

    user.update_columns(settings: settings.merge('enabled_map_layers' => layers - [FAMILY_MAP_LAYER]))
  end

  def cleanup_on_departure
    revoke_inherited_subscription

    # Disable location sharing for departing user
    user.update_family_location_sharing!(false) if user.family_sharing_stored?
    disable_family_map_layer

    # Expire all pending location requests involving the departing user
    Family::LocationRequest
      .pending
      .where('requester_id = ? OR target_user_id = ?', user_id, user_id)
      .update_all(status: Family::LocationRequest.statuses[:expired], updated_at: Time.current)
  rescue StandardError => e
    ExceptionReporter.call(e, "Error cleaning up on family departure: #{e.message}")
  end

  def revoke_inherited_subscription
    return if DawarichSettings.self_hosted?
    return if owner?
    return unless user.sub_source_none?

    user.update!(plan: :lite, status: :inactive, active_until: nil)
  end
end
