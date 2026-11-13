# frozen_string_literal: true

# Every non-demo Place its owner tagged "home" (any case) becomes one open-ended Home.
class SeedHomesFromHomeTag < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      INSERT INTO homes (user_id, place_id, created_at, updated_at)
      SELECT DISTINCT places.user_id, places.id, NOW(), NOW()
      FROM places
      JOIN taggings ON taggings.taggable_type = 'Place' AND taggings.taggable_id = places.id
      JOIN tags ON tags.id = taggings.tag_id AND tags.user_id = places.user_id
      WHERE LOWER(tags.name) = 'home' AND places.demo = FALSE AND tags.demo = FALSE
        AND NOT EXISTS (SELECT 1 FROM homes WHERE homes.place_id = places.id)
    SQL
  end

  # Nothing to undo: seeded rows are indistinguishable from Homes users made since.
  def down; end
end
