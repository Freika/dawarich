# frozen_string_literal: true

class AddPrivacyRadiusToTags < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :tags, :privacy_radius_meters, :integer
    add_index :tags,
              :privacy_radius_meters,
              where: 'privacy_radius_meters IS NOT NULL',
              algorithm: :concurrently
  end

  def down
    remove_index :tags,
                 column: :privacy_radius_meters,
                 where: 'privacy_radius_meters IS NOT NULL',
                 algorithm: :concurrently
    remove_column :tags, :privacy_radius_meters
  end
end
