# frozen_string_literal: true

class AddProductAnalyticsWebObservedAtToUsers < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:users, :product_analytics_web_observed_at)

    add_column :users, :product_analytics_web_observed_at, :datetime
  end

  def down
    return unless column_exists?(:users, :product_analytics_web_observed_at)

    remove_column :users, :product_analytics_web_observed_at
  end
end
