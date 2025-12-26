# frozen_string_literal: true

class ValidateArchivalForeignKeys < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :points_raw_data_archives, :users
    validate_foreign_key :points, :points_raw_data_archives
  end
end
