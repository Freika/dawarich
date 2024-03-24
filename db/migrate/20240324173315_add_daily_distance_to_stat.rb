class AddDailyDistanceToStat < ActiveRecord::Migration[7.1]
  def change
    add_column :stats, :daily_distance, :jsonb, default: {}
  end
end
