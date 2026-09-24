# frozen_string_literal: true

class AddProductAnalyticsConsentToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :product_analytics_consent, :boolean
    add_column :users, :product_analytics_id, :uuid
    add_column :users, :product_analytics_consented_at, :datetime
    add_column :users, :product_analytics_revoked_at, :datetime
    add_index :users, :product_analytics_id, unique: true
  end
end
