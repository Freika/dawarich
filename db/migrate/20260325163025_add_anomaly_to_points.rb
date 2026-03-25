class AddAnomalyToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :points, :anomaly, :boolean
    add_index :points, :anomaly, where: 'anomaly IS NOT TRUE',
              name: 'index_points_on_not_anomaly',
              algorithm: :concurrently
  end
end
