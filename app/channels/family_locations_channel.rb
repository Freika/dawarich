# frozen_string_literal: true

class FamilyLocationsChannel < ApplicationCable::Channel
  def subscribed
    return reject if current_user.nil?
    return reject unless DawarichSettings.family_feature_available_for?(current_user)
    return reject unless current_user.in_family?

    stream_for current_user.family
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
