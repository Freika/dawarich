class AddPrivacyRadiusToTags < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :tags, :privacy_radius_meters, :integer
    add_index :tags, :privacy_radius_meters, where: "privacy_radius_meters IS NOT NULL", algorithm: :concurrently
  end
end
