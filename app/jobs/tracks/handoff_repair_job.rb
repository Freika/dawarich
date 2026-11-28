# frozen_string_literal: true

class Tracks::HandoffRepairJob < ApplicationJob
  queue_as :low_priority
  retry_on Tracks::PerUserLock::AcquisitionTimeout, wait: 15.minutes, attempts: 4

  def perform(user_id, from_timestamp)
    user = User.find_by(id: user_id)
    return unless user

    from = Time.zone.at(from_timestamp)
    Tracks::PerUserLock.with_user_lock(user.id) do
      Tracks::MetadataRefresher.new(user).call if Tracks::HandoffSplitter.new(user).repair(from:).positive?
    end
  end
end
