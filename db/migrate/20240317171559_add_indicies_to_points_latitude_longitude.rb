class AddIndiciesToPointsLatitudeLongitude < ActiveRecord::Migration[7.1]
  def change
    add_index :points, [:latitude, :longitude]
  end
end
