# frozen_string_literal: true

# first_map_data_viewed means "the first time this account saw its own
# imported data". Users who imported before the event existed have seen it
# already, so they get a seeded row and never send it. Raw SQL keeps the
# migration independent of the models' later schema.
#
# Only completed imports that produced points count: a user whose imports all
# failed has not seen any data yet.
#
# event enum: 1 = first_map_data_viewed; import status enum: 2 = completed
class SeedFirstMapDataViewed < ActiveRecord::Migration[8.1]
  def up
    return if DawarichSettings.self_hosted?

    execute <<~SQL.squish
      INSERT INTO analytics_events (user_id, event, dedup_key, properties, delivered_at, created_at, updated_at)
      SELECT user_id, 1, 'first_map_data_viewed:' || user_id, '{"seeded": true}', NOW(), NOW(), NOW()
      FROM (SELECT DISTINCT user_id FROM imports WHERE demo = false AND status = 2 AND points_count > 0) AS importers
      ON CONFLICT (dedup_key) DO NOTHING
    SQL
  end

  def down
    return unless table_exists?(:analytics_events)

    execute <<~SQL.squish
      DELETE FROM analytics_events WHERE event = 1 AND properties @> '{"seeded": true}'
    SQL
  end
end
