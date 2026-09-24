# frozen_string_literal: true

class AddProductAnalyticsFirstMobileUploadAt < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :product_analytics_first_mobile_upload_at, :datetime
  end
end
