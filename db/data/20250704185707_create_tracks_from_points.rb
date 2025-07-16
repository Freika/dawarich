# frozen_string_literal: true

class CreateTracksFromPoints < ActiveRecord::Migration[8.0]
  def up
    puts "Starting bulk track creation for all users..."

    total_users = User.count
    processed_users = 0

    User.find_each do |user|
      points_count = user.tracked_points.count

      if points_count > 0
        puts "Enqueuing track creation for user #{user.id} (#{points_count} points)"

        # Use explicit parameters for bulk historical processing:
        # - No time limits (start_at: nil, end_at: nil) = process ALL historical data
        # - Replace strategy = clean slate, removes any existing tracks first
        Tracks::CreateJob.perform_later(
          user.id,
          start_at: nil,
          end_at: nil,
          mode: :daily
        )

        processed_users += 1
      else
        puts "Skipping user #{user.id} (no tracked points)"
      end
    end

    puts "Enqueued track creation jobs for #{processed_users}/#{total_users} users"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
