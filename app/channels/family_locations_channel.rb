# frozen_string_literal: true

class FamilyLocationsChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_user.nil?
    return reject unless DawarichSettings.family_feature_available_for?(current_user)
    return reject unless current_user.in_family?

    family = current_user.family

    # Membership is re-checked on every message, not only at subscribe time: a
    # member removed while this socket stays open must stop receiving the
    # family's live locations. Removing the row revokes neither the stream nor
    # the connection, so the guard lives here, the one place every broadcast
    # passes through.
    stream_for family, coder: ActiveSupport::JSON do |location|
      next if location['user_id'].to_s == current_user.id.to_s
      next stop_all_streams unless Family::Membership.exists?(user_id: current_user.id, family_id: family.id)

      transmit location
    end
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
