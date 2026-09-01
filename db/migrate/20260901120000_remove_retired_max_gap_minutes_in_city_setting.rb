# frozen_string_literal: true

class RemoveRetiredMaxGapMinutesInCitySetting < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE users SET settings = settings - 'max_gap_minutes_in_city'
      WHERE settings ?| array['max_gap_minutes_in_city']
    SQL
  end

  def down; end
end
