# frozen_string_literal: true

class AddFileTypeToExports < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :exports, :file_type, :integer, default: 0, null: false
    add_index :exports, :file_type, algorithm: :concurrently
  end

  def down
    remove_index :exports, :file_type, algorithm: :concurrently
    remove_column :exports, :file_type
  end
end
