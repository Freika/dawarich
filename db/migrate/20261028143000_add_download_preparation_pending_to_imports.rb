# frozen_string_literal: true

class AddDownloadPreparationPendingToImports < ActiveRecord::Migration[8.1]
  def up
    add_column :imports, :download_preparation_pending, :boolean, default: false, null: false, if_not_exists: true
  end

  def down
    remove_column :imports, :download_preparation_pending, if_exists: true if table_exists?(:imports)
  end
end
