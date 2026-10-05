# frozen_string_literal: true

class Points::NightlyReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform
    config = Geocoding::Config.resolved_config
    return unless config.enabled?
    return if JobOwnership.with_owner(Geocoding::NightlyCommands::KEY) { :owned } == :not_owner

    processed_user_ids = Set.new
    slot = Integrations::SchedulingCommands.slot(self, nil)
    root = Geocoding::NightlyCommands.root(slot)

    Point.not_reverse_geocoded.in_batches(of: 1000) do |batch|
      result = JobOwnership.with_owner(Geocoding::NightlyCommands::KEY) do
        rows = batch.pluck(:user_id, :id).select { |_, id| Geocoding::NightlyCommands.claim(root, id) }
        rows.group_by(&:first).each do |user_id, points|
          Geocoding::ReverseCommands.enqueue_points(user_id, points.map(&:last), force: true,
                                                    producer: 'Points::NightlyReverseGeocodingJob')
          processed_user_ids.add(user_id)
        end
      end
      break if result == :not_owner
    end

    processed_user_ids.each do |user_id|
      Cache::InvalidateUserCaches.new(user_id).call
    end
  end
end
