# frozen_string_literal: true

class AddProductAnalyticsConsentToUsers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  COLUMNS = {
    product_analytics_consent: :boolean,
    product_analytics_id: :uuid,
    product_analytics_consented_at: :datetime,
    product_analytics_revoked_at: :datetime
  }.freeze
  INDEX_NAME = 'index_users_on_product_analytics_id'

  def up
    COLUMNS.each do |name, type|
      add_column :users, name, type unless column_exists?(:users, name)
    end
    return if index_name_exists?(:users, INDEX_NAME)

    add_index :users, :product_analytics_id, unique: true, algorithm: :concurrently, name: INDEX_NAME
  end

  def down
    remove_index :users, name: INDEX_NAME, algorithm: :concurrently if index_name_exists?(:users, INDEX_NAME)
    COLUMNS.each_key do |name|
      remove_column :users, name if column_exists?(:users, name)
    end
  end
end
