# frozen_string_literal: true

class FamilyLocationsChannel < ApplicationCable::Channel
  def subscribed
    return reject unless family_feature_enabled?
    return reject unless current_user.in_family?

    stream_for current_user.family
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end

  private

  def family_feature_enabled?
    DawarichSettings.family_feature_enabled?
  end
end
