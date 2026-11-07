# frozen_string_literal: true

class AddProductAnalyticsFirstMobileUploadAt < ActiveRecord::Migration[8.0]
  def up
    return if column_exists?(:users, :product_analytics_first_mobile_upload_at)

    add_column :users, :product_analytics_first_mobile_upload_at, :datetime
  end

  def down
    return unless column_exists?(:users, :product_analytics_first_mobile_upload_at)

    remove_column :users, :product_analytics_first_mobile_upload_at
  end
end
