# frozen_string_literal: true

class AddUnavailableImportScopeToExports < ActiveRecord::Migration[8.0]
  def up
    # A restored missing/legacy source must never become an unfiltered export.
    add_column :exports, :import_scope_unavailable, :boolean, default: false, null: false, if_not_exists: true
  end

  def down
    remove_column :exports, :import_scope_unavailable, if_exists: true
  end
end
