# frozen_string_literal: true

class AddProductAnalyticsWebObservedAtToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :product_analytics_web_observed_at, :datetime
  end
end
