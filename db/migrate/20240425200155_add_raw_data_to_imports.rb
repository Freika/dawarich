# frozen_string_literal: true

class AddRawDataToImports < ActiveRecord::Migration[7.1]
  def change
    add_column :imports, :raw_data, :jsonb
  end
end
