class AddCountryNameToPoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :points, :country_name, :string
    add_index :points, :country_name, algorithm: :concurrently

    DataMigrations::BackfillCountryNameJob.perform_later
  end
end
