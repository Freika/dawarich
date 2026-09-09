# frozen_string_literal: true

class RemoveRetiredVisitDetectionSettings < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE users SET settings = settings - 'stay_max_gap_minutes' - 'visit_density_fill_enabled'
      WHERE settings ?| array['stay_max_gap_minutes','visit_density_fill_enabled']
    SQL
  end

  def down; end
end
