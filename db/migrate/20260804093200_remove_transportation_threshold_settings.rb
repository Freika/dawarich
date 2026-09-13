# frozen_string_literal: true

class RemoveTransportationThresholdSettings < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE users SET settings = settings - 'transportation_thresholds'
                                 - 'transportation_expert_thresholds'
                                 - 'transportation_expert_mode'
      WHERE settings ?| array['transportation_thresholds','transportation_expert_thresholds','transportation_expert_mode']
    SQL
  end

  def down; end
end
