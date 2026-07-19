# frozen_string_literal: true

class AddLegacyTrackerPointsIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :points, :user_id,
              where: "tracker_id IN ('google-maps-timeline-export', 'google-maps-phone-timeline-export')",
              name: 'idx_points_user_id_legacy_tracker',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
