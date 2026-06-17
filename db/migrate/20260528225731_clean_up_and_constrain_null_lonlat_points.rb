# frozen_string_literal: true

class CleanUpAndConstrainNullLonlatPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  CONSTRAINT_NAME = 'points_lonlat_null'

  def up
    backfill_lonlat_from_legacy_columns
    delete_points_without_coordinates

    return if constraint_present?

    add_check_constraint :points, 'lonlat IS NOT NULL', name: CONSTRAINT_NAME, validate: false
  end

  def down
    remove_check_constraint :points, name: CONSTRAINT_NAME if constraint_present?
  end

  private

  def backfill_lonlat_from_legacy_columns
    result = execute(<<~SQL.squish)
      UPDATE points
      SET lonlat = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
      WHERE lonlat IS NULL
        AND latitude IS NOT NULL
        AND longitude IS NOT NULL
    SQL

    Rails.logger.info("[#{self.class.name}] backfilled #{result.cmd_tuples} point(s) from legacy latitude/longitude")
  end

  def delete_points_without_coordinates
    affected_user_ids = select_values('SELECT DISTINCT user_id FROM points WHERE lonlat IS NULL').compact
    deleted = execute('DELETE FROM points WHERE lonlat IS NULL').cmd_tuples

    Rails.logger.info("[#{self.class.name}] deleted #{deleted} point(s) without coordinates")

    resync_points_counters(affected_user_ids)
  end

  def resync_points_counters(user_ids)
    user_ids.each do |user_id|
      execute(<<~SQL.squish)
        UPDATE users
        SET points_count = (SELECT COUNT(*) FROM points WHERE points.user_id = #{user_id.to_i})
        WHERE id = #{user_id.to_i}
      SQL
    end
  end

  def constraint_present?
    select_value("SELECT 1 FROM pg_constraint WHERE conname = '#{CONSTRAINT_NAME}'").present?
  end
end
