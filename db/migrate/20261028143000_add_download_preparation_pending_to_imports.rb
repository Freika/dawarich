# frozen_string_literal: true

class AddDownloadPreparationPendingToImports < ActiveRecord::Migration[8.1]
  def change
    add_column :imports, :download_preparation_pending, :boolean, default: false, null: false
  end
end
