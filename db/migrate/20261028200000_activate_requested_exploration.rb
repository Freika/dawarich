# frozen_string_literal: true

class ActivateRequestedExploration < ActiveRecord::Migration[8.1]
  def up
    add_column :exploration_states, :activated_at, :datetime
    execute <<~SQL
      UPDATE exploration_states SET activated_at = updated_at
      WHERE snapshot_id IS NOT NULL OR requested_at IS NOT NULL OR failed_at IS NOT NULL
        OR EXISTS (SELECT 1 FROM achievement_city_selections c WHERE c.user_id = exploration_states.user_id)
    SQL
  end

  def down
    remove_column :exploration_states, :activated_at
  end
end
