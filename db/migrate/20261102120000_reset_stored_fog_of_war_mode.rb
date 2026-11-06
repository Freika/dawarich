# frozen_string_literal: true

# The fog mode default moved from points to hexagons. A stored "points" was
# often written by the old Reset rather than chosen, so every stored value is
# dropped and users get the new default.
class ResetStoredFogOfWarMode < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE users SET settings = settings - 'fog_of_war_mode'
      WHERE settings ?| array['fog_of_war_mode']
    SQL
  end

  # Nothing to restore: the removed values carried no reliable user choice.
  def down; end
end
