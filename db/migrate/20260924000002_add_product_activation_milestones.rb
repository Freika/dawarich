# frozen_string_literal: true

class AddProductActivationMilestones < ActiveRecord::Migration[8.0]
  COLUMNS = [
    %i[users product_analytics_first_point_at],
    %i[users product_analytics_activated_at],
    %i[imports product_analytics_reported_at]
  ].freeze

  def up
    COLUMNS.each do |table, name|
      add_column table, name, :datetime unless column_exists?(table, name)
    end
  end

  def down
    COLUMNS.each do |table, name|
      remove_column table, name if column_exists?(table, name)
    end
  end
end
