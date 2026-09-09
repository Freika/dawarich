# frozen_string_literal: true

class ValidatePointsTrackForeignKey < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BATCH_SIZE = 10_000

  def up
    return unless foreign_key_exists?(:points, :tracks, column: :track_id)

    detach_dangling_points
    validate_foreign_key :points, :tracks, column: :track_id
  end

  def down; end

  private

  def detach_dangling_points
    loop do
      detached = connection.update(<<~SQL.squish)
        UPDATE points SET track_id = NULL
        WHERE id IN (
          SELECT p.id FROM points p
          LEFT JOIN tracks t ON t.id = p.track_id
          WHERE p.track_id IS NOT NULL AND t.id IS NULL
          LIMIT #{BATCH_SIZE}
        )
      SQL

      break if detached.zero?
    end
  end
end
