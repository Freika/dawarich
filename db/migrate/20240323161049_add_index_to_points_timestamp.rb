class AddIndexToPointsTimestamp < ActiveRecord::Migration[7.1]
  def change
    add_index :points, :timestamp
  end
end
