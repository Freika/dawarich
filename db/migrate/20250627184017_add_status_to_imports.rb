# frozen_string_literal: true

class AddStatusToImports < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :imports, :status, :integer, default: 0, null: false
    add_index :imports, :status, algorithm: :concurrently

    Import.update_all(status: :completed)
  end
end
