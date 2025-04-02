# frozen_string_literal: true

class AddFormatStartAtEndAtToExports < ActiveRecord::Migration[8.0]
  def change
    add_column :exports, :file_format, :integer, default: 0
    add_column :exports, :start_at, :datetime
    add_column :exports, :end_at, :datetime
  end
end
