# frozen_string_literal: true

class AddProcessingStartedAtToExportsAndImports < ActiveRecord::Migration[8.0]
  def change
    add_column :exports, :processing_started_at, :datetime
    add_column :imports, :processing_started_at, :datetime
  end
end
