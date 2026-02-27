# frozen_string_literal: true

class AddProcessedToImports < ActiveRecord::Migration[7.1]
  def change
    add_column :imports, :processed, :integer, default: 0
  end
end
