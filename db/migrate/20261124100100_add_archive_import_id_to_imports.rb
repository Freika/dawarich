# frozen_string_literal: true

# Links the imports extracted from one uploaded ZIP to that upload. No foreign
# key: the archive's own import row is deleted once its files are extracted.
class AddArchiveImportIdToImports < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :imports, :archive_import_id, :bigint, if_not_exists: true
    add_index :imports, :archive_import_id, where: 'archive_import_id IS NOT NULL',
                                            algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :imports, :archive_import_id, algorithm: :concurrently, if_exists: true
    remove_column :imports, :archive_import_id, if_exists: true
  end
end
