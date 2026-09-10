# frozen_string_literal: true

# Mobile clients receive invalidations, never coordinates. HTTP remains the
# authority for membership and sharing permissions. Batch point notifications
# so an import or a fast tracker cannot turn into one HTTP refresh per point.
class FamilyUpdatesChannel < ApplicationCable::Channel
  periodically :flush_location_change, every: 5.seconds
  periodically :verify_access, every: 30.seconds

  def subscribed
    return reject unless family_api_user

    @family_id = family_api_user.family&.id
    return reject unless authorized?

    stream_for family_api_user.family, coder: ActiveSupport::JSON do |_message|
      transmit({ type: 'sharing_changed' }) if verify_access
    end
    stream_from FamilyLocationsChannel.broadcasting_for(family_api_user.family),
                coder: ActiveSupport::JSON do |_message|
      @locations_changed = true
    end
  end

  private

  def authorized?
    user = connection.authorized_family_api_user
    user && user.family&.id == @family_id
  end

  def verify_access
    return true if authorized?

    stop_all_streams
    transmit({ type: 'access_revoked' })
    false
  end

  def flush_location_change
    return unless @locations_changed

    @locations_changed = false
    transmit({ type: 'locations_changed' }) if verify_access
  end
end
