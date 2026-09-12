# frozen_string_literal: true

class ChangeFlightsExternalIdToBigint < ActiveRecord::Migration[8.1]
  def up
    change_column :flights, :external_id, :bigint, null: false
  end

  def down
    change_column :flights, :external_id, :integer, null: false
  end
end
