# frozen_string_literal: true

class FamilyLocationsChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_user.nil?
    return reject unless DawarichSettings.family_feature_available_for?(current_user)
    return reject unless current_user.in_family?

    stream_for current_user.family, coder: ActiveSupport::JSON do |location|
      transmit location unless location['user_id'].to_s == current_user.id.to_s
    end
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
