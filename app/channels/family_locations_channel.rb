# frozen_string_literal: true

class FamilyLocationsChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user.family_feature_available?
    return reject unless current_user.in_family?

    stream_for current_user.family
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end
