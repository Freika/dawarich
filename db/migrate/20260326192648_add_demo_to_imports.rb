# frozen_string_literal: true

class AddDemoToImports < ActiveRecord::Migration[8.0]
  def change
    add_column :imports, :demo, :boolean, default: false, null: false unless column_exists?(:imports, :demo)
  end
end
