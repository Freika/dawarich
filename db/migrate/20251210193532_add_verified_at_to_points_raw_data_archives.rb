class AddVerifiedAtToPointsRawDataArchives < ActiveRecord::Migration[8.0]
  def change
    add_column :points_raw_data_archives, :verified_at, :datetime
  end
end
