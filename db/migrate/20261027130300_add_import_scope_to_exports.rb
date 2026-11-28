# frozen_string_literal: true

class AddImportScopeToExports < ActiveRecord::Migration[8.0]
  def up
    # Keep the scope if the import is deleted; clearing it would broaden a queued export.
    add_column :exports, :import_id, :bigint, if_not_exists: true
  end

  def down
    remove_column :exports, :import_id, if_exists: true
  end
end
