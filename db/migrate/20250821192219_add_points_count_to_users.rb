class AddPointsCountToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :points_count, :integer, default: 0, null: false

    # Initialize counter cache for existing users using background job
    reversible do |dir|
      dir.up do
        DataMigrations::PrefillPointsCounterCacheJob.perform_later
      end
    end
  end
end
