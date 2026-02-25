# frozen_string_literal: true

class RemoveDuplicatePoints < ActiveRecord::Migration[8.0]
  def up
    # Find duplicate groups using a subquery
    duplicate_groups =
      Point.select('latitude, longitude, timestamp, user_id, COUNT(*) as count')
           .group('latitude, longitude, timestamp, user_id')
           .having('COUNT(*) > 1')

    Rails.logger.debug "Duplicate groups found: #{duplicate_groups.length}"

    duplicate_groups.each do |group|
      points = Point.where(
        latitude: group.latitude,
        longitude: group.longitude,
        timestamp: group.timestamp,
        user_id: group.user_id
      ).order(id: :asc)

      # Keep the latest record and destroy all others
      latest = points.last
      points.where.not(id: latest.id).destroy_all
    end
  end

  def down
    # This migration cannot be reversed
    raise ActiveRecord::IrreversibleMigration
  end
end
