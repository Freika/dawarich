# frozen_string_literal: true

class TrackSegmentPolicy < ApplicationPolicy
  def update?
    return false if user.nil?

    record.track.user_id == user.id
  end
end
