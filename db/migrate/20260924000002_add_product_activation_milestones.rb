# frozen_string_literal: true

class AddProductActivationMilestones < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :product_analytics_first_point_at, :datetime
    add_column :users, :product_analytics_activated_at, :datetime
    add_column :imports, :product_analytics_reported_at, :datetime
  end
end
